drop table tmp_ytd_of_symbols;
create table tmp_ytd_of_symbols as
select calendar_year, calendar_month, symbol, ytd, price, MARKET_CAP
from vw_ytd_of_symbols
;

INSERT INTO "TRADER"."ACCOUNT" (BALANCE) VALUES ('10000')
;
commit
;

select * from STOCK_PRICES
 order by PRICE_DATE
;
INSERT INTO market_calendar (market_day_no, market_date)
SELECT MARKET_DAY_NO, MARKET_DATE
  from VW_MARKET_DAY
;
commit
;
