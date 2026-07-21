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

  select sp2.symbol, sp1.price price1, sp2.PRICE price2,
         (sp2.PRICE / sp1.PRICE - 1) * 100 as ytd,
         sp2.PRICE_DATE datum
    from STOCK_PRICES sp1
    join STOCK_PRICES sp2 on sp1.symbol = sp2.symbol
   where sp1.PRICE_DATE = to_date('2025.12.31','yyyy.mm.dd')
     and sp2.PRICE_DATE >= to_date('2026.02.17','yyyy.mm.dd')
     and sp2.symbol = 'STX'
   order by sp2.PRICE_DATE
;

with ytd as (
  select sp2.symbol, sp1.price price1, sp2.PRICE price2,
         (sp2.PRICE / sp1.PRICE - 1) * 100 as ytd,
         sp2.PRICE_DATE datum
    from STOCK_PRICES sp1
    join STOCK_PRICES sp2 on sp1.symbol = sp2.symbol
   where sp1.PRICE_DATE = to_date('2025.12.31','yyyy.mm.dd')
),
account as (
  select 10000 balance, 5 num_of_stocks from dual
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
),
gewinn_pro_abschnitt as (
select market_day_no, kaufdatum, verkaufsdatum, gewinn from gewinn
  cross join account
  join MARKET_CALENDAR mc on mc.MARKET_DATE = kaufdatum
    and mod(market_day_no, num_of_stocks) = 0
)
select kaufdatum, verkaufsdatum, gewinn,
       exp(sum(ln(1 + gewinn/100)) over (order by kaufdatum)) as wert
  from gewinn_pro_abschnitt
 where kaufdatum >= to_date('2026.02.17','yyyy.mm.dd')
 order by kaufdatum
;
