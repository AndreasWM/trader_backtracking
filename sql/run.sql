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
truncate table market_calendar;
INSERT INTO market_calendar (market_day_no, market_date)
SELECT MARKET_DAY_NO, MARKET_DATE
  from VW_MARKET_DAY
;
commit
;

drop table tmp_ichimoku;
create table tmp_ichimoku as
select SYMBOL, PRICE_DATE, PRICE, HIGH, LOW, market_cap, TENKAN_SEN, KIJUN_SEN, SENKOU_SPAN_A, SENKOU_SPAN_B, CHIKOU_SPAN
from VW_ICHIMOKU
;
drop INDEX ix_tmp_ichimoku_sym_date;
CREATE INDEX ix_tmp_ichimoku_sym_date
  ON TMP_ICHIMOKU (PRICE_DATE, SYMBOL)
;
exec dbms_stats.gather_table_stats(user, 'TMP_ICHIMOKU', cascade => true)
;
