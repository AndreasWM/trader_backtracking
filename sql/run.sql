drop table tmp_ytd_of_symbols;
create table tmp_ytd_of_symbols as
select calendar_year, calendar_month, symbol, ytd, price, MARKET_CAP
from vw_ytd_of_symbols
;

INSERT INTO "TRADER"."ACCOUNT" (BALANCE) VALUES ('10000')
;
commit
;
