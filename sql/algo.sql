-- CREATE TABLE "STOCK_PRICES" 
--    (	"SYMBOL" VARCHAR2(20 BYTE) NOT NULL ENABLE, 
-- 	"PRICE_DATE" DATE NOT NULL ENABLE, 
-- 	"PRICE" BINARY_DOUBLE
--    )
-- ;

with ytd as (
  select sp2.symbol, sp1.price price1, sp2.PRICE price2, (sp2.PRICE / sp1.PRICE - 1) * 100 as ytd, sp2.PRICE_DATE PRICE_DATE
    from STOCK_PRICES sp1
    join STOCK_PRICES sp2 on sp1.symbol = sp2.symbol
  where sp1.PRICE_DATE = to_date('2025.12.31','yyyy.mm.dd')
)
select * from ytd
  where ytd.ytd > 200
  and ytd.PRICE_DATE >= to_date('2026.05.25','yyyy.mm.dd')
 order by ytd.PRICE_DATE, ytd.symbol
;

with ytd as (
  select sp2.symbol, sp1.price price1, sp2.PRICE price2,
         (sp2.PRICE / sp1.PRICE - 1) * 100 as ytd,
         sp2.PRICE_DATE PRICE_DATE
    from STOCK_PRICES sp1
    join STOCK_PRICES sp2 on sp1.symbol = sp2.symbol
   where sp1.PRICE_DATE = to_date('2025.12.31','yyyy.mm.dd')
),
ranked as (
  select ytd.*,
         row_number() over (partition by PRICE_DATE order by ytd desc) as rn
    from ytd
)
select symbol, PRICE_DATE, price2 price
  from ranked
 where rn <= 20
   and PRICE_DATE >= to_date('2026.02.01','yyyy.mm.dd')
 order by PRICE_DATE, rn
;

with base_selection as (
  select sp2.symbol,
         (sp2.PRICE / sp1.PRICE - 1) * 100 as ytd,
         sp2.PRICE_DATE PRICE_DATE
    from STOCK_PRICES sp1
    join STOCK_PRICES sp2 on sp1.symbol = sp2.symbol
   where sp1.PRICE_DATE = to_date('2025.12.31','yyyy.mm.dd')
     and sp2.PRICE_DATE = to_date('2026.02.02','yyyy.mm.dd')
),
ranked as (
  select b.*, row_number() over (order by ytd desc) as rn
    from base_selection b
),
selected_symbols as (
  select symbol
    from ranked
   where rn <= 10
),
symbol_count as (
  select count(*) as cnt from selected_symbols
),
prices as (
  select s.symbol, sp.PRICE_DATE, sp.PRICE, sc.cnt,
         row_number() over (partition by s.symbol order by sp.PRICE_DATE) - 1 as day_idx
    from selected_symbols s
    join STOCK_PRICES sp on sp.symbol = s.symbol
    cross join symbol_count sc
   where sp.PRICE_DATE between to_date('2026.03.31','yyyy.mm.dd')
                           and to_date('2026.05.19','yyyy.mm.dd')
),
depot_wert as (
  select symbol, PRICE_DATE, PRICE, round(depot_wert, 2) as depot_wert
    from prices
    MODEL
      PARTITION BY (symbol)
      DIMENSION BY (day_idx)
      MEASURES (PRICE, PRICE_DATE, cnt, cast(null as binary_double) as depot_wert)
      RULES SEQUENTIAL ORDER (
        depot_wert[0] = 10000 / cnt[0],
        depot_wert[day_idx > 0] ORDER BY day_idx =
            depot_wert[cv(day_idx) - 1] * PRICE[cv(day_idx)] / PRICE[cv(day_idx) - 1]
      )
)
select dw.price_date, sum(dw.depot_wert) depot_wert
  from depot_wert dw
 group by PRICE_DATE
 order by PRICE_DATE
;

with base_selection as (
  select sp2.symbol,
         (sp2.PRICE / sp1.PRICE - 1) * 100 as ytd,
         sp2.PRICE_DATE PRICE_DATE
    from STOCK_PRICES sp1
    join STOCK_PRICES sp2 on sp1.symbol = sp2.symbol
   where sp1.PRICE_DATE = to_date('2025.12.31','yyyy.mm.dd')
     and sp2.PRICE_DATE = to_date('2026.02.02','yyyy.mm.dd')
),
ranked as (
  select b.*, row_number() over (order by ytd desc) as rn
    from base_selection b
),
selected_symbols as (
  select symbol
    from ranked
   where rn <= 10
),
symbol_count as (
  select count(*) as cnt from selected_symbols
),
prices as (
  select s.symbol, sp.PRICE_DATE, sp.PRICE, sc.cnt,
         row_number() over (partition by s.symbol order by sp.PRICE_DATE) - 1 as day_idx
    from selected_symbols s
    join STOCK_PRICES sp on sp.symbol = s.symbol
    cross join symbol_count sc
   where sp.PRICE_DATE between to_date('2026.03.31','yyyy.mm.dd')
                           and to_date('2026.05.19','yyyy.mm.dd')
)
select * from prices
;