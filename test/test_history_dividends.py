import yfinance as yf

# Aktie laden (Beispiel: Realty Income)
ticker = yf.Ticker("O")

# Historische Kurse und Dividenden abrufen
history = ticker.history(period="5y")
dividends = ticker.dividends

# Alternativ liefert yfinance auch direkt fundamentale Zeitreihen,
# allerdings oft unvollständig. Sicherer ist die manuelle Berechnung:
print(dividends)