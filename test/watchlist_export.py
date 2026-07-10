"""
Watchlist-Exportprogramm
Liest die neueste TradingView-Watchlist-CSV und erzeugt eine Textdatei
im Format EXCHANGE:SYMBOL*ANZAHL+... (10 Aktien pro Zeile).

Anzahl = round(10000 / Preis_in_EUR)
"""

import os
import glob
import csv

# ── Konfiguration ────────────────────────────────────────────────────────────

WATCHLIST_DIR = "."
OUTPUT_FILE   = "llb_dividende.txt"
INVEST_EUR    = 10_000.0
PER_LINE      = 10

# 1 EUR = x Währung (ungefähre Richtwerte)
RATES = {
    "EUR": 1.0,
    "USD": 1.08,
    "AUD": 1.67,
    "GBP": 0.86,
    "GBX": 86.0,   # Britische Pence (1/100 GBP)
    "CHF": 0.94,
    "SGD": 1.45,
    "HKD": 8.42,
    "JPY": 163.0,
    "CAD": 1.48,
}

# ── Dateiverwaltung ──────────────────────────────────────────────────────────

class WatchlistReader:
    def get_latest_watchlist_file(self, dir: str) -> str:
        pattern = os.path.join(dir, 'Watchlist*.csv')
        files = glob.glob(pattern)

        if not files:
            raise FileNotFoundError(
                f"Keine Datei mit Muster 'Watchlist*.csv' in {dir}"
            )

        return max(files, key=os.path.getmtime)

# ── Hauptlogik ───────────────────────────────────────────────────────────────

def load_watchlist(filepath: str) -> list[dict]:
    with open(filepath, newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def build_entries(rows: list[dict]) -> list[str]:
    entries = []
    for row in rows:
        symbol   = row["Symbol"].strip()
        exchange = row["Exchange"].strip()
        currency = row["Price - Currency"].strip().upper()

        try:
            price = float(row["Price"].replace(",", "."))
        except ValueError:
            print(f"[WARNUNG] Ungültiger Preis für {symbol}, übersprungen.")
            continue

        if currency not in RATES:
            print(f"[WARNUNG] Unbekannte Währung '{currency}' für {symbol}, übersprungen.")
            continue

        price_eur = price / RATES[currency]

        if price_eur <= 0:
            print(f"[WARNUNG] Preis ≤ 0 für {symbol}, übersprungen.")
            continue

        anzahl = round(INVEST_EUR / price_eur)
        entries.append(f"{exchange}:{symbol}*{anzahl}")

    return entries


def format_output(entries: list[str]) -> str:
    lines = []
    for i in range(0, len(entries), PER_LINE):
        lines.append("+".join(entries[i:i + PER_LINE]))
    return "\n".join(lines)


def main():
    reader = WatchlistReader()
    filepath = reader.get_latest_watchlist_file(WATCHLIST_DIR)
    print(f"Lese: {filepath}")

    rows = load_watchlist(filepath)
    print(f"{len(rows)} Aktien geladen.")

    entries = build_entries(rows)
    output_str = format_output(entries)

    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        f.write(output_str + "\n")

    print(f"\nAusgabe ({len(entries)} Aktien) → {OUTPUT_FILE}")
    print("─" * 60)
    print(output_str)
    print("─" * 60)


if __name__ == "__main__":
    main()