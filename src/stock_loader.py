import os
import sys
import yfinance as yf
import pandas as pd
import oracledb
from concurrent.futures import ThreadPoolExecutor
from itertools import islice

project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if project_root not in sys.path:
    sys.path.insert(0, project_root)

from lib.tv_scanner import TV_Scanner
from lib.stock_util import StockUtil

# ── Verbindungsparameter ────────────────────────────────────────────────────────
DB_USER     = "TRADER"
DB_PASSWORD = os.getenv("ORACLE_TRADER_PW")
DB_DSN      = "(description= (retry_count=20)(retry_delay=3)(address=(protocol=tcps)(port=1522)(host=adb.eu-frankfurt-1.oraclecloud.com))(connect_data=(service_name=g0c5cfd076541df_iweaacmgy3oa0pcw_low.adb.oraclecloud.com))(security=(ssl_server_dn_match=yes)))"

# Tuning-Parameter
CHUNK_SIZE         = 50_000  # Zeilen pro executemany-Aufruf
COMMIT_EVERY       = 500_000 # Zeilen zwischen Commits
POOL_MIN           = 2       # Minimale Verbindungen im Pool
POOL_MAX           = 5       # Maximale Verbindungen im Pool
MAX_STOCKS         = 1000    # Max. Anzahl zu ladender Aktien (für Scanner-Query)
MARKET_CAP_WORKERS = 20      # Parallele Threads für Aktienanzahl-Abruf

# Ichimoku-Parameter (Standard-Perioden)
ICHIMOKU_TENKAN_PERIOD   = 9    # Conversion Line
ICHIMOKU_KIJUN_PERIOD    = 26   # Base Line
ICHIMOKU_SENKOU_B_PERIOD = 52   # Senkou Span B
ICHIMOKU_DISPLACEMENT    = 26   # Vorwärtsversatz der Cloud (Standard: = Kijun-Periode)


class StockLoader:
    def __init__(self):
        self._util = StockUtil()
        self._sc   = TV_Scanner()
        # red_list = self._util.read_symbols(self._util.get_latest_watchlist_file(self._util.get_data_dir_linux()))
        red_list = self._unwanted_tickers = self._util.read_symbols(self._util.get_latest_do_not_trade_file())

        other_unwanted_stocks = ["SNDK"]
        self._unwanted_tickers = red_list #+ other_unwanted_stocks
        self._pool: oracledb.ConnectionPool | None = None

    # ── Connection Pool ─────────────────────────────────────────────────────────

    def _get_pool(self) -> oracledb.ConnectionPool:
        """Erstellt den Connection-Pool beim ersten Aufruf (lazy)."""
        if self._pool is None:
            self._pool = oracledb.create_pool(
                user=DB_USER,
                password=DB_PASSWORD,
                dsn=DB_DSN,
                min=POOL_MIN,
                max=POOL_MAX,
                increment=1,
            )
        return self._pool

    def close_pool(self) -> None:
        if self._pool is not None:
            self._pool.close()
            self._pool = None

    # ── Download ────────────────────────────────────────────────────────────────

    def download_in_batches(
        self, tickers: list[str], batch_size: int = 200, **kwargs
    ) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame]:
        """
        Lädt Close, Open, High und Low – alle vier werden in die DB-Spalten
        übernommen, High/Low zusätzlich für die Ichimoku-Berechnung.
        """
        close_data, open_data, high_data, low_data = [], [], [], []
        num_batches = (len(tickers) + batch_size - 1) // batch_size
        for i in range(0, len(tickers), batch_size):
            print(f"Downloading batch {i // batch_size + 1} of {num_batches}")
            batch = tickers[i:i + batch_size]
            df = yf.download(batch, **kwargs, progress=False)
            if df is None or df.empty:
                print(f"  ⚠️  No data for batch {i // batch_size + 1}, skipping...")
                continue
            close_data.append(df["Close"])
            open_data.append(df["Open"])
            high_data.append(df["High"])
            low_data.append(df["Low"])
        if not close_data:
            raise ValueError("No data downloaded for any batch.")
        return (
            pd.concat(close_data, axis=1),
            pd.concat(open_data, axis=1),
            pd.concat(high_data, axis=1),
            pd.concat(low_data, axis=1),
        )

    def load_symbols(self) -> list[str]:
        symbols = self._sc.query_us(
            tickers_to_exclude=self._unwanted_tickers,
            market_cap=10_000_000_000,
            length=MAX_STOCKS,
        )
        symbols = [s.replace(".", "-") for s in symbols if "/" not in s]
        return symbols

    def load_prices_and_shares(
        self, symbols: list[str]
    ) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame, dict[str, float | None]]:
        """
        Lädt Preise (Close/Open/High/Low) und aktuelle Aktienanzahl parallel
        und berechnet daraus die Ichimoku-Wolke (Span A / Span B).

        Rückgabe: (close_prices, open_prices, high_prices, low_prices, span_a, span_b, shares)
        """
        if not symbols:
            print("⚠️  Keine Symbole zum Laden")
            return pd.DataFrame(), pd.DataFrame(), pd.DataFrame(), pd.DataFrame(), pd.DataFrame(), pd.DataFrame(), {}

        print(f"📥 Lade Preise und Aktienanzahl für {len(symbols)} Symbole...")

        def _fetch_shares(symbol: str) -> tuple[str, float | None]:
            try:
                return symbol, yf.Ticker(symbol).fast_info.shares
            except Exception:
                return symbol, None

        with ThreadPoolExecutor(max_workers=MARKET_CAP_WORKERS) as pool:
            shares_future = pool.map(_fetch_shares, symbols)
            close_prices, open_prices, high_prices, low_prices = self.download_in_batches(
                tickers=symbols,
                batch_size=50,
                period="3y",
                # auto_adjust=False: liefert die tatsächlich gehandelten
                # (nominalen) Kurse statt um Dividenden/Splits rückwirkend
                # bereinigter Werte. Mit auto_adjust=True würde sich der
                # historische Close mit jeder neuen Dividendenzahlung
                # nachträglich leicht nach unten verschieben.
                auto_adjust=False,
            )
            shares = dict(shares_future)

        fetched = sum(1 for v in shares.values() if v is not None)
        print(f"✅ Preise geladen, Aktienanzahl: {fetched} vorhanden, {len(shares) - fetched} fehlend")

        span_a, span_b = self.calculate_ichimoku_spans(high_prices, low_prices)

        return close_prices, open_prices, high_prices, low_prices, span_a, span_b, shares

    # ── Ichimoku-Berechnung ─────────────────────────────────────────────────────

    def calculate_ichimoku_spans(
        self, high: pd.DataFrame, low: pd.DataFrame
    ) -> tuple[pd.DataFrame, pd.DataFrame]:
        """
        Berechnet Senkou Span A und Senkou Span B der Ichimoku-Wolke,
        inklusive des klassischen 26-Perioden-Vorwärtsversatzes (Displacement),
        wie er auch bei TradingView Standard ist.

        Tenkan-sen (9)  = (Hoch_9  + Tief_9)  / 2
        Kijun-sen  (26) = (Hoch_26 + Tief_26) / 2
        Span A (roh)    = (Tenkan-sen + Kijun-sen) / 2
        Span B (roh, 52) = (Hoch_52 + Tief_52) / 2

        Displacement: der für Datum T angezeigte Cloud-Wert wird eigentlich
        aus den Daten bis (T - 26 Handelstage) berechnet und 26 Perioden in
        die Zukunft projiziert. Technisch heißt das: raw-Werte werden per
        shift(26) um 26 Zeilen nach VORNE verschoben, sodass an Position T
        der Wert steht, der ursprünglich aus den Daten von (T - 26) stammt.

        rolling() und shift() arbeiten spaltenweise, d.h. jedes Symbol
        (Spalte) wird unabhängig über sein eigenes Zeitfenster berechnet.
        """
        tenkan = (
            high.rolling(ICHIMOKU_TENKAN_PERIOD).max()
            + low.rolling(ICHIMOKU_TENKAN_PERIOD).min()
        ) / 2
        kijun = (
            high.rolling(ICHIMOKU_KIJUN_PERIOD).max()
            + low.rolling(ICHIMOKU_KIJUN_PERIOD).min()
        ) / 2

        raw_span_a = (tenkan + kijun) / 2
        raw_span_b = (
            high.rolling(ICHIMOKU_SENKOU_B_PERIOD).max()
            + low.rolling(ICHIMOKU_SENKOU_B_PERIOD).min()
        ) / 2

        # Vorwärtsversatz: Wert von (T - displacement) erscheint an Position T.
        #
        # Hinweis: TradingView (Pine Script) zählt Bars ab Index 0 und
        # projiziert die Werte relativ dazu. Ein reiner positionaler
        # shift(26) landet dadurch einen Handelstag zu spät gegenüber der
        # TradingView-Darstellung. Empirisch abgeglichen (siehe AVGO
        # 06.04.2026) muss der tatsächliche Zeilenversatz daher
        # (ICHIMOKU_DISPLACEMENT - 1) betragen, um exakt mit TradingView
        # übereinzustimmen.
        effective_shift = ICHIMOKU_DISPLACEMENT - 1
        span_a = raw_span_a.shift(effective_shift)
        span_b = raw_span_b.shift(effective_shift)

        return span_a, span_b

    # ── Transformation ──────────────────────────────────────────────────────────

    def to_long_format(
        self,
        prices: pd.DataFrame,
        open_: pd.DataFrame,
        high: pd.DataFrame,
        low: pd.DataFrame,
        span_a: pd.DataFrame,
        span_b: pd.DataFrame,
        shares: dict[str, float | None] | None = None,
    ) -> pd.DataFrame:
        """
        Wide → Long mit den Spalten
        symbol, price_date, price, open, high, low, span_a, span_b, market_cap.

        market_cap wird als price × shares berechnet (Näherung: konstante
        Aktienanzahl über den gesamten Zeitraum).
        """
        if prices.empty:
            return pd.DataFrame(
                columns=["symbol", "price_date", "price", "open", "high", "low", "span_a", "span_b", "market_cap"]
            )

        # Diagnose: Yahoo Finance liefert den Kurs des jüngsten Handelstages
        # oft nicht für alle Symbole gleichzeitig (Verzögerung im Feed).
        # dropna() weiter unten entfernt diese Zeilen sonst kommentarlos.
        latest_date  = prices.index.max()
        latest_row   = prices.loc[latest_date]
        total_syms   = len(latest_row)
        missing_syms = int(latest_row.isna().sum())
        if missing_syms > 0:
            available_syms = total_syms - missing_syms
            print(
                f"⚠️  Für {latest_date.date()} liegen nur bei {available_syms} von "
                f"{total_syms} Symbolen Kursdaten vor ({missing_syms} fehlen noch "
                f"und werden für diesen Tag ausgelassen)."
            )

        def _melt(df: pd.DataFrame, value_name: str) -> pd.DataFrame:
            df = df.copy()
            df.index = pd.to_datetime(df.index).normalize()
            return (
                df.reset_index()
                .rename(columns={"Date": "price_date"})
                .melt(id_vars="price_date", var_name="symbol", value_name=value_name)
            )

        price_long  = _melt(prices, "price")
        open_long   = _melt(open_, "open")
        high_long   = _melt(high, "high")
        low_long    = _melt(low, "low")
        span_a_long = _melt(span_a, "span_a")
        span_b_long = _melt(span_b, "span_b")

        long_df = (
            price_long
            .merge(open_long, on=["symbol", "price_date"], how="left")
            .merge(high_long, on=["symbol", "price_date"], how="left")
            .merge(low_long, on=["symbol", "price_date"], how="left")
            .merge(span_a_long, on=["symbol", "price_date"], how="left")
            .merge(span_b_long, on=["symbol", "price_date"], how="left")
            .dropna(subset=["price"])
            .sort_values(["symbol", "price_date"])
            .reset_index(drop=True)
        )

        # Historische Market Cap = price × aktuelle Stückanzahl
        if shares:
            shares_series = long_df["symbol"].map(shares)
            long_df["market_cap"] = long_df["price"] * shares_series
        else:
            long_df["market_cap"] = None

        return long_df[["symbol", "price_date", "price", "open", "high", "low", "span_a", "span_b", "market_cap"]]

    # ── Oracle Bulk-Insert ──────────────────────────────────────────────────────

    @staticmethod
    def _iter_chunks(iterable, size: int):
        """Liefert den Iterator in Blöcken der gewünschten Größe."""
        it = iter(iterable)
        while True:
            chunk = list(islice(it, size))
            if not chunk:
                break
            yield chunk

    def _prepare_rows(self, long_df: pd.DataFrame) -> list[tuple]:
        """
        Konvertiert den DataFrame in eine Liste von
        (symbol, price_date, price, open, high, low, span_a, span_b, market_cap)-Tupeln.

        Bewusst spaltenweise (statt itertuples) implementiert: itertuples()
        liefert dynamisch erzeugte NamedTuples, deren Feldtypen von
        statischen Type-Checkern (Pyright/Pylance) nicht zuverlässig
        aufgelöst werden können und zu falschen Attribut-Fehlern führen.
        """
        symbols     = long_df["symbol"].tolist()
        price_dates = pd.to_datetime(long_df["price_date"]).dt.date.tolist()

        prices  = pd.to_numeric(long_df["price"], errors="coerce")
        opens   = pd.to_numeric(long_df["open"], errors="coerce")
        highs   = pd.to_numeric(long_df["high"], errors="coerce")
        lows    = pd.to_numeric(long_df["low"], errors="coerce")
        span_a  = pd.to_numeric(long_df["span_a"], errors="coerce")
        span_b  = pd.to_numeric(long_df["span_b"], errors="coerce")
        mcaps   = pd.to_numeric(long_df["market_cap"], errors="coerce")

        price_list      = [None if pd.isna(v) else float(v) for v in prices]
        open_list       = [None if pd.isna(v) else float(v) for v in opens]
        high_list       = [None if pd.isna(v) else float(v) for v in highs]
        low_list        = [None if pd.isna(v) else float(v) for v in lows]
        span_a_list     = [None if pd.isna(v) else float(v) for v in span_a]
        span_b_list     = [None if pd.isna(v) else float(v) for v in span_b]
        market_cap_list = [None if pd.isna(v) else float(v) for v in mcaps]

        return list(
            zip(
                symbols, price_dates, price_list, open_list, high_list, low_list,
                span_a_list, span_b_list, market_cap_list,
            )
        )

    def save_to_oracle(
        self,
        long_df: pd.DataFrame,
        table_name: str = "stock_prices",
        truncate_first: bool = False,
    ) -> None:
        """
        Schreibt Millionen von Zeilen effizient per Bulk-Insert in Oracle.

        Strategie:
        - oracledb native (kein SQLAlchemy-Overhead)
        - executemany() mit vorbereiteten Tupeln (CHUNK_SIZE Zeilen pro Aufruf)
        - Commit alle COMMIT_EVERY Zeilen (kein riesiges Undo-Segment)
        - setinputsizes() für maximale Bind-Performance
        - Optional: TRUNCATE vor dem Insert (schneller als DELETE)
        """
        if long_df.empty:
            print("⚠️  Keine Daten zum Speichern.")
            return

        total = len(long_df)
        print(f"💾 Schreibe {total:,} Zeilen in Tabelle '{table_name}' …")

        rows = self._prepare_rows(long_df)
        sql  = (
            f"INSERT INTO {table_name} "
            f"(symbol, price_date, price, open, high, low, span_a, span_b, market_cap) "
            f"VALUES (:1, :2, :3, :4, :5, :6, :7, :8, :9)"
        )

        pool = self._get_pool()
        with pool.acquire() as conn:
            conn.autocommit = False

            # TRUNCATE auf einem eigenen Cursor ausführen – dieser Cursor
            # bekommt NIE setinputsizes(), da TRUNCATE keine Bind-Variablen hat.
            if truncate_first:
                with conn.cursor() as ddl_cursor:
                    ddl_cursor.execute(f"TRUNCATE TABLE {table_name}")
                print(f"  🗑️  Tabelle '{table_name}' geleert.")

            # Eigener Cursor nur für die parametrisierten Inserts
            cursor = conn.cursor()

            # Bind-Typen einmalig deklarieren → weniger Overhead pro Zeile
            cursor.setinputsizes(
                oracledb.DB_TYPE_VARCHAR,            # symbol
                oracledb.DB_TYPE_DATE,               # price_date
                oracledb.DB_TYPE_BINARY_DOUBLE,      # price
                oracledb.DB_TYPE_BINARY_DOUBLE,      # open
                oracledb.DB_TYPE_BINARY_DOUBLE,      # high
                oracledb.DB_TYPE_BINARY_DOUBLE,      # low
                oracledb.DB_TYPE_BINARY_DOUBLE,      # span_a
                oracledb.DB_TYPE_BINARY_DOUBLE,      # span_b
                oracledb.DB_TYPE_BINARY_DOUBLE,      # market_cap (NULL-fähig)
            )

            inserted  = 0
            committed = 0

            for chunk in self._iter_chunks(rows, CHUNK_SIZE):
                cursor.executemany(sql, chunk, batcherrors=True)

                # Fehlerhafte Einzelzeilen protokollieren, aber weiterlaufen
                for err in cursor.getbatcherrors():
                    print(f"  ⚠️  Zeile {err.offset}: {err.message}")

                inserted += len(chunk)

                # Commit in definierten Intervallen
                if inserted - committed >= COMMIT_EVERY:
                    conn.commit()
                    committed = inserted
                    pct = inserted / total * 100
                    print(f"  ✔  {inserted:>10,} / {total:,} Zeilen committed ({pct:.1f} %)")

            conn.commit()   # Rest-Zeilen committen
            cursor.close()

        print(f"✅ Fertig – {inserted:,} Zeilen erfolgreich in '{table_name}' geschrieben.")


def main():
    loader = StockLoader()
    try:
        symbols                                           = loader.load_symbols()
        prices, open_, high, low, span_a, span_b, shares  = loader.load_prices_and_shares(symbols)
        long_df                                           = loader.to_long_format(
            prices, open_, high, low, span_a, span_b, shares=shares
        )

        print(f"\n📊 Tabelle: {len(long_df):,} Zeilen, {long_df['symbol'].nunique()} Symbole")

        loader.save_to_oracle(
            long_df,
            table_name="stock_prices",
            truncate_first=True,
        )
    finally:
        loader.close_pool()


if __name__ == "__main__":
    main()