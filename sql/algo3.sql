create or replace view v_depot_kette as
with ytd as (
  select sp2.symbol, sp1.price price1, sp2.PRICE price2,
         (sp2.PRICE / sp1.PRICE - 1) * 100 as ytd,
         sp2.PRICE_DATE datum
    from STOCK_PRICES sp1
    join STOCK_PRICES sp2 on sp1.symbol = sp2.symbol
   where sp1.PRICE_DATE = to_date('2025.12.31','yyyy.mm.dd')
),
account as (
  select 10000 balance, 20 num_of_stocks from dual
),
ranked as (
  select ytd.*,
         row_number() over (partition by datum order by ytd desc) as rn
    from ytd
),
preis as (
  select symbol, datum, price2 price, round(BALANCE / price2 / num_of_stocks) as quantity
    from ranked
    cross join account
   where rn <= num_of_stocks
),
summen as (
  select p1.datum kaufdatum, sp.PRICE_DATE verkaufsdatum,
         sum(p1.price*p1.quantity) summe1, sum(sp.price*p1.quantity) summe2
    from preis p1
    join MARKET_CALENDAR mc1 on mc1.MARKET_DATE = p1.datum
    join MARKET_CALENDAR mc2 on mc2.MARKET_DAY_NO = mc1.MARKET_DAY_NO + 10
    join STOCK_PRICES sp on sp.symbol = p1.symbol
                and sp.PRICE_DATE = mc2.MARKET_DATE
  group by p1.datum, sp.PRICE_DATE
),
gewinn as (
  select kaufdatum, verkaufsdatum, (summe2/summe1 -1)*100 gewinn
    from summen
  -- bewusst kein Datumsfilter -- die Kette braucht die volle Historie
),
kette (kaufdatum, verkaufsdatum, gewinn, lvl) as (
    select kaufdatum, verkaufsdatum, gewinn, 1
      from gewinn
     where kaufdatum = (select min(kaufdatum) from gewinn)
    union all
    select g.kaufdatum, g.verkaufsdatum, g.gewinn, k.lvl + 1
      from gewinn g
      join kette k on g.kaufdatum = k.verkaufsdatum
)
select kaufdatum, verkaufsdatum, gewinn
  from kette;

select kaufdatum, verkaufsdatum, gewinn,
       exp(sum(ln(1 + gewinn/100)) over (order by kaufdatum)) as wert
  from v_depot_kette
 where kaufdatum >= to_date('2026.02.17','yyyy.mm.dd')
 order by kaufdatum;

select *
  from v_depot_kette
;
select kaufdatum, verkaufsdatum, gewinn,
       exp(sum(ln(1 + gewinn/100)) over (order by kaufdatum)) as wert
  from v_depot_kette
;

with perf as (
  select sp2.symbol, sp2.PRICE,
         (sp2.PRICE / sp1.PRICE - 1) * 100 as perf,
         sp2.PRICE_DATE datum
    from tmp_ICHIMOKU sp1
    join tmp_ICHIMOKU sp2 on sp1.symbol = sp2.symbol
  --  where sp1.PRICE_DATE = add_months(sp2.PRICE_DATE, -12)
   where sp1.PRICE_DATE = to_date('2025.12.31','yyyy.mm.dd')
     and sp2.price > sp2.SENKOU_SPAN_A
     and sp2.price > sp2.SENKOU_SPAN_B
    --  and sp2.symbol = 'STX'
),
params as (
  select 10000 balance, 10 num_of_stocks, 3 day_diff from dual
),
ranked as (
  select perf.*,
         row_number() over (partition by datum order by perf desc) as rn
    from perf
),
preis as (
  select symbol, datum, price, round(BALANCE / price / num_of_stocks) as quantity
    from ranked
    cross join params
   where rn <= num_of_stocks
),
summen as (
  select p1.datum kaufdatum, sp.PRICE_DATE verkaufsdatum,
         sum(p1.price*p1.quantity) summe1, sum(sp.price*p1.quantity) summe2
    from preis p1
    cross join params
    join MARKET_CALENDAR mc1 on mc1.MARKET_DATE = p1.datum
    join MARKET_CALENDAR mc2 on mc2.MARKET_DAY_NO = mc1.MARKET_DAY_NO + day_diff
    join STOCK_PRICES sp on sp.symbol = p1.symbol
                and sp.PRICE_DATE = mc2.MARKET_DATE
  group by p1.datum, sp.PRICE_DATE
),
gewinn as (
  select kaufdatum, verkaufsdatum, (summe2/summe1 -1)*100 gewinn
    from summen
),
gewinn_pro_abschnitt as (
select market_day_no, kaufdatum, verkaufsdatum, gewinn from gewinn
  cross join params
  join MARKET_CALENDAR mc on mc.MARKET_DATE = kaufdatum
    and mod(market_day_no, day_diff) = 0
),
ergebnis as (
  select kaufdatum, verkaufsdatum, gewinn,
        exp(sum(ln(1 + gewinn/100)) over (order by kaufdatum)) as wert
    from gewinn_pro_abschnitt
  where kaufdatum >= to_date('2026.02.24','yyyy.mm.dd')
  order by kaufdatum
)
select * from ergebnis
-- select * from preis
--   where datum >= to_date('2026.02.24','yyyy.mm.dd')
-- where symbol = 'NVDA'
-- order by kaufdatum asc
;

with perf as (
  select sp2.symbol, sp2.PRICE,
         (sp2.PRICE / sp1.PRICE - 1) * 100 as perf,
         sp2.PRICE_DATE datum
    from tmp_ICHIMOKU sp1
    join tmp_ICHIMOKU sp2 on sp1.symbol = sp2.symbol
   where sp1.PRICE_DATE = add_months(sp2.PRICE_DATE, -12)
     and (sp2.price > sp2.SENKOU_SPAN_A
     and sp2.price > sp2.SENKOU_SPAN_B) or
        (sp2.price < sp2.SENKOU_SPAN_A
     and sp2.price < sp2.SENKOU_SPAN_B)
    --  and sp2.symbol = 'STX'
),
params as (
  select 10000 balance, 10 num_of_stocks, 3 day_diff from dual
)
select * from perf
 where datum = to_date('2026.07.23','yyyy.mm.dd')
;

select count(*)
  from MARKET_CALENDAR
;
select distinct symbol, market_cap from STOCK_PRICES
 where PRICE_DATE between to_date('2026.07.29','yyyy.mm.dd') and to_date('2026.07.29','yyyy.mm.dd')
order by market_cap desc
;

create or replace view vw_auswahl_pro_tag as
with params as (
  select 100000 balance, 20 num_of_stocks from dual
),
longshort as (
  select sp2.symbol, sp2.PRICE, sp2.market_cap,
         (sp2.PRICE / sp1.PRICE - 1) * 100 as perf,
         sp2.PRICE_DATE datum
         , case when sp2.price > sp2.SENKOU_SPAN_A and sp2.price > sp2.SENKOU_SPAN_B then 'L'
                else case when sp2.price < sp2.SENKOU_SPAN_A and sp2.price < sp2.SENKOU_SPAN_B then 'S' else 'N' end
           end direction
    from tmp_ICHIMOKU sp2
    join tmp_ICHIMOKU sp1 on sp1.symbol = sp2.symbol
                        --  and sp1.PRICE_DATE = add_months(sp2.PRICE_DATE, -12)
                         and sp1.PRICE_DATE = to_date('2025.12.31','yyyy.mm.dd')
   where sp2.market_cap > 50000000000
),
ranked as (
  select ls.*,
         row_number() over (partition by ls.datum order by perf desc) as rn
    from longshort ls
)
select r.symbol, r.price, r.market_cap, r.perf, r.datum, r.direction,
       round(BALANCE / price / num_of_stocks)
       * case when r.direction = 'L' then 1 else case when r.direction = 'S' then -1 else 0 end end as quantity
  from ranked r
 cross join params
   where rn <= num_of_stocks
;

with summen as (
  select p1.datum kaufdatum, sp.PRICE_DATE verkaufsdatum,
         sum(p1.price*p1.quantity) summe1,
         sum(sp.price*p1.quantity) summe2
    from vw_auswahl_pro_tag p1
    join MARKET_CALENDAR mc1 on mc1.MARKET_DATE = p1.datum
    join MARKET_CALENDAR mc2 on mc2.MARKET_DAY_NO = mc1.MARKET_DAY_NO + 1
    join STOCK_PRICES sp on sp.symbol = p1.symbol and sp.PRICE_DATE = mc2.MARKET_DATE
  group by p1.datum, sp.PRICE_DATE
),
gewinn as (
  select kaufdatum, verkaufsdatum, (summe2/summe1 -1)*100 gewinn
    from summen
  where kaufdatum between to_date('2025.08.06','yyyy.mm.dd') and to_date('2025.08.06','yyyy.mm.dd')
)
select g.*, exp(sum(ln(1 + gewinn/100)) over (order by kaufdatum)) as wert
  from gewinn g
;
        
select *
  from VW_AUSWAHL_PRO_TAG
 where datum between to_date('2025.08.06','yyyy.mm.dd') and to_date('2025.08.06','yyyy.mm.dd')
;
