"""
Diagnose-Skript: Ermittelt den exakt korrekten Displacement-Wert für die
Ichimoku-Berechnung, indem die UNVERSCHOBENEN (rohen) Span-Werte über
mehrere Tage ausgegeben werden.

Vorgehen:
1. SYMBOL / TARGET_DATE / TV_SPAN_A / TV_SPAN_B unten für den jeweiligen
   Testfall anpassen (z.B. einmal für AVGO/06.04.2026, einmal für
   ADI/24.06.2026) und das Skript lokal ausführen.
2. In der Ausgabe die Zeile suchen, deren raw SPAN_A/SPAN_B exakt mit dem
   TradingView-Wert übereinstimmt.
3. Die Spalte "Handelstage frueher" dieser Zeile ist der tatsächlich
   korrekte Displacement-Wert für diesen Testfall.
4. Stimmen die Ergebnisse beider Testfälle überein → das ist der korrekte,
   allgemeingültige Displacement-Wert. Falls nicht → das Problem liegt
   nicht an einem festen Shift, sondern vermutlich an abweichenden
   historischen High/Low-Werten innerhalb des Rolling-Fensters.
"""

import datetime
import yfinance as yf
import pandas as pd

SYMBOL      = "ADI"
TARGET_DATE = datetime.date(2026, 6, 24)
TV_SPAN_A   = 403.19
TV_SPAN_B   = 367.13

TENKAN_PERIOD   = 9
KIJUN_PERIOD    = 26
SENKOU_B_PERIOD = 52

df = yf.download(SYMBOL, period="2y", auto_adjust=False, progress=False)
if df is None or df.empty:
    raise ValueError(f"Keine Daten für {SYMBOL} heruntergeladen.")

# Robust gegen unterschiedliche yfinance-Rückgabeformen (Single- vs. MultiIndex)
high_col = df["High"]
low_col  = df["Low"]
high = high_col[SYMBOL] if isinstance(high_col, pd.DataFrame) else high_col
low  = low_col[SYMBOL]  if isinstance(low_col, pd.DataFrame)  else low_col

tenkan = (high.rolling(TENKAN_PERIOD).max() + low.rolling(TENKAN_PERIOD).min()) / 2
kijun  = (high.rolling(KIJUN_PERIOD).max()  + low.rolling(KIJUN_PERIOD).min())  / 2
raw_span_a = (tenkan + kijun) / 2
raw_span_b = (high.rolling(SENKOU_B_PERIOD).max() + low.rolling(SENKOU_B_PERIOD).min()) / 2

# Bewusst über reine Python-Listen statt pandas-Index-Objekte gearbeitet,
# um typprüfungs-anfällige Konstrukte (Timestamp, Index[Any].date()) zu
# vermeiden.
dates       = pd.to_datetime(raw_span_a.index).date.tolist()
span_a_vals = raw_span_a.tolist()
span_b_vals = raw_span_b.tolist()

target_idx = None
for i, d in enumerate(dates):
    if d >= TARGET_DATE:
        target_idx = i
        break

if target_idx is None:
    raise ValueError(f"Zieldatum {TARGET_DATE} liegt außerhalb des geladenen Zeitraums.")

print(f"{'Datum':12} {'Handelstage frueher':>20} {'raw SPAN_A':>12} {'raw SPAN_B':>12}")
for offset in range(20, 33):  # rund um den erwarteten Bereich (25/26) suchen
    idx = target_idx - offset
    if idx < 0:
        continue
    d  = dates[idx]
    sa = span_a_vals[idx]
    sb = span_b_vals[idx]
    if sa is None or sb is None or pd.isna(sa) or pd.isna(sb):
        continue
    is_match = abs(sa - TV_SPAN_A) < 0.05 and abs(sb - TV_SPAN_B) < 0.05
    marker = " <-- TREFFER?" if is_match else ""
    print(f"{d}   {offset:>18}   {sa:>12.2f} {sb:>12.2f}{marker}")

print(f"\nZiel (TradingView, {TARGET_DATE}): SPAN_A={TV_SPAN_A}  SPAN_B={TV_SPAN_B}")
print("Der Offset-Wert bei der Zeile mit '<-- TREFFER?' ist der korrekte Displacement-Wert.")