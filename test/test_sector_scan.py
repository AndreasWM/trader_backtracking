from tradingview_screener.query import Query

count, df = (
    Query()
    .select('name', 'close', 'volume', 'market_cap_basic', 'sector')
    .set_index('SYML:NASDAQ;UTY')          # ← das ist der korrekte Weg
    .order_by('market_cap_basic', ascending=False)
    .limit(50)
    .get_scanner_data()
)

print(f"Anzahl Treffer: {count}")
print(df)