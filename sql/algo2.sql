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
    -- and datum >= to_date('2026.02.01','yyyy.mm.dd')
),
summen as (
  select p1.datum kaufdatum, sp.PRICE_DATE verkaufsdatum, sum(p1.price*p1.quantity) summe1, sum(sp.price*p1.quantity) summe2
    from preis p1
    join MARKET_CALENDAR mc1 on mc1.MARKET_DATE = p1.datum
    join MARKET_CALENDAR mc2 on mc2.MARKET_DAY_NO = mc1.MARKET_DAY_NO + 10
    join STOCK_PRICES sp on sp.symbol = p1.symbol
                and sp.PRICE_DATE = mc2.MARKET_DATE
  group by p1.datum, sp.PRICE_DATE
),
gewinn as (
  select kaufdatum, verkaufsdatum, (summe2/summe1 -1)*100 gewinn from summen
   where kaufdatum >= to_date('2026.02.01','yyyy.mm.dd')
),
kette (kaufdatum, verkaufsdatum, gewinn, lvl) as (
    select kaufdatum, verkaufsdatum, gewinn, 1
      from gewinn
     where kaufdatum = (select min(kaufdatum) from gewinn)   -- Startzeile
    union all
    select g.kaufdatum, g.verkaufsdatum, g.gewinn, k.lvl + 1
      from gewinn g
      join kette k on g.kaufdatum = k.verkaufsdatum          -- nächste Zeile anhängen
),
depot_wert as (
  SELECT kaufdatum, verkaufsdatum, gewinn, wert
  FROM (
      SELECT KAUFDATUM, verkaufsdatum,
            GEWINN,
            ROW_NUMBER() OVER (ORDER BY KAUFDATUM) AS rn
      FROM KETTE
  )
  MODEL
      DIMENSION BY (rn)
      MEASURES (kaufdatum, verkaufsdatum, gewinn, CAST(1 AS BINARY_DOUBLE) AS wert)
      RULES AUTOMATIC ORDER (
          wert[rn > 1] = wert[CV() - 1] * (1 + gewinn[CV()] / 100)
      )
  ORDER BY rn
)
select kaufdatum, verkaufsdatum, gewinn, wert
  from depot_wert
--  where kaufdatum >= to_date('2026.02.01','yyyy.mm.dd')
 order by kaufdatum
;
