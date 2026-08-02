import os
import sys
from tradingview_screener.query import Query
from tradingview_screener.column import Column

project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if project_root not in sys.path:
    sys.path.insert(0, project_root)

class TV_Scanner:
    def safe_float(self, value, default=0.0):
        return float(value) if value is not None else default
    
    def always_true(self):
        return Column("exchange") != "INVALID"

    def query_us(self, tickers_to_exclude: list[str], market_cap: int, length: int) -> list[str]:
        cond_stocktype = Column('type').isin(['stock','dr'])
        cond_subtype = Column('subtype') != 'preferred'
        cond_exchange = Column('exchange').isin(['NASDAQ', 'NYSE'])
        cond_market_cap = Column('market_cap_basic') > market_cap
        conditions = [
            cond_stocktype,
            cond_subtype,
            cond_exchange,
            cond_market_cap,
        ]
        if tickers_to_exclude:
            conditions.append(Column('name').not_in(tickers_to_exclude))
        
        q = Query() \
            .select(
                'name',
                'close',
                'exchange',
                'type',
                'subtype',
                'Perf.YTD',
                'market_cap_basic',
            ) \
            .where(*conditions) \
            .order_by('market_cap_basic', ascending=False) \
            .limit(length)
        
        _, scanner_data = q.get_scanner_data()
        
        scanner_data = scanner_data.drop(columns=['ticker'])
        scanner_data = scanner_data.rename(columns={
            "name": "symbol",
            "close": "price",
        })
        
        # print(",".join(scanner_data.columns))
        symbol_list = []
        for _, row in scanner_data.iterrows():
            # print(",".join(str(v) for v in row.values))
            symbol = row['symbol']
            symbol_list.append(symbol)

        return symbol_list
