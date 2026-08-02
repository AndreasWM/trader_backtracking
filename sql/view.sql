create or replace view vw_ytd_of_symbols as
with stock_prices_year_end as (
SELECT symbol, calendar_year, price as price_year_end
FROM (
    SELECT 
        symbol,
        calendar_year,
        price,
        market_cap,
        ROW_NUMBER() OVER (
            PARTITION BY symbol, calendar_year
            ORDER BY price_date DESC
        ) AS rn
    FROM stock_prices
)
WHERE rn = 1
  and calendar_year < extract(year from current_date)
),
ytd_percentages as (
select sp.symbol, sp.price, sp.MARKET_CAP, (sp.price - spe.price_year_end) / spe.price_year_end * 100 as ytd,
        sp.calendar_year, sp.calendar_month, sp.calendar_day
  from stock_prices sp
  join stock_prices_year_end spe on sp.symbol = spe.symbol
                                and sp.calendar_year = spe.calendar_year+1
),
rebalance_dates as (
  select symbol, calendar_year, calendar_month, max(calendar_day) last_day_of_month
    from ytd_percentages
  group by symbol, calendar_year, calendar_month
)
select yp.calendar_year, yp.calendar_month, yp.symbol, yp.ytd, yp.price, yp.MARKET_CAP
  from rebalance_dates rd
  join ytd_percentages yp on rd.symbol = yp.symbol
                        and rd.last_day_of_month = yp.calendar_day
                        and rd.calendar_month = yp.calendar_month
                        and rd.calendar_year = yp.calendar_year
 where yp.MARKET_CAP > 100000000000
;

create or replace view vw_top10_ytd_of_symbols as
SELECT calendar_year, calendar_month, symbol, price, MARKET_CAP
FROM (
    SELECT
        calendar_year,
        calendar_month,
        symbol,
        price,
        MARKET_CAP,
        RANK() OVER (PARTITION BY calendar_year, calendar_month ORDER BY ytd DESC) AS rank
    FROM tmp_ytd_of_symbols
)
WHERE rank <= 10
  AND calendar_year = 2026
ORDER BY calendar_year, calendar_month, rank
;

create or replace view vw_invest as
with balance as (
  SELECT COALESCE(
    (SELECT balance 
      FROM account
      ORDER BY account_date DESC
      FETCH FIRST 1 ROWS ONLY),
    10000
  ) AS balance
  FROM dual
),
number_of_symbols as (
  select calendar_year, calendar_month, count(*) number_of_symbols
    from vw_top10_ytd_of_symbols
  group by calendar_year, calendar_month
),
quantity_to_buy as (
  select th.calendar_year, th.calendar_month, th.symbol, th.price, round(b.balance / ns.number_of_symbols / th.price) as quantity
    from vw_top10_ytd_of_symbols th
    join balance b on 1=1
    join number_of_symbols ns on th.calendar_year = ns.calendar_year AND th.calendar_month = ns.calendar_month
)
select calendar_year, calendar_month, symbol, quantity, quantity * price as total_price
  from quantity_to_buy
order by calendar_year, calendar_month, symbol
;

create or replace view vw_market_day as
SELECT ROW_NUMBER() OVER (ORDER BY price_date) AS market_day_no,
       price_date market_date
FROM (
    SELECT DISTINCT price_date
    FROM stock_prices
)
ORDER BY price_date
;

create or replace view vw_ichimoku as
WITH base AS (
    SELECT
        SYMBOL,
        PRICE_DATE,
        PRICE,
        HIGH,
        LOW,
        MARKET_CAP,
        -- Tenkan-sen (Conversion Line): (Hoch9 + Tief9) / 2
        ( MAX(HIGH) OVER (PARTITION BY SYMBOL ORDER BY PRICE_DATE
                          ROWS BETWEEN 8 PRECEDING AND CURRENT ROW)
        + MIN(LOW)  OVER (PARTITION BY SYMBOL ORDER BY PRICE_DATE
                          ROWS BETWEEN 8 PRECEDING AND CURRENT ROW)
        ) / 2 AS TENKAN_SEN,

        -- Kijun-sen (Base Line): (Hoch26 + Tief26) / 2
        ( MAX(HIGH) OVER (PARTITION BY SYMBOL ORDER BY PRICE_DATE
                          ROWS BETWEEN 25 PRECEDING AND CURRENT ROW)
        + MIN(LOW)  OVER (PARTITION BY SYMBOL ORDER BY PRICE_DATE
                          ROWS BETWEEN 25 PRECEDING AND CURRENT ROW)
        ) / 2 AS KIJUN_SEN,

        -- Rohwert für Senkou Span B: (Hoch52 + Tief52) / 2  (noch ohne Verschiebung)
        ( MAX(HIGH) OVER (PARTITION BY SYMBOL ORDER BY PRICE_DATE
                          ROWS BETWEEN 51 PRECEDING AND CURRENT ROW)
        + MIN(LOW)  OVER (PARTITION BY SYMBOL ORDER BY PRICE_DATE
                          ROWS BETWEEN 51 PRECEDING AND CURRENT ROW)
        ) / 2 AS SENKOU_B_RAW
    FROM STOCK_PRICES
),
calc AS (
    SELECT
        SYMBOL,
        PRICE_DATE,
        PRICE,
        HIGH,
        LOW,
        MARKET_CAP,
        TENKAN_SEN,
        KIJUN_SEN,
        -- Rohwert für Senkou Span A: (Tenkan + Kijun) / 2 (noch ohne Verschiebung)
        (TENKAN_SEN + KIJUN_SEN) / 2 AS SENKOU_A_RAW,
        SENKOU_B_RAW
    FROM base
)
SELECT
    SYMBOL,
    PRICE_DATE,
    PRICE,
    HIGH,
    LOW,
    MARKET_CAP,
    TENKAN_SEN,
    KIJUN_SEN,
    -- Senkou Span A/B werden 26 Perioden in die Zukunft geplottet
    -- -> der an Tag T berechnete Wert erscheint am Chart bei Tag T+26
    LAG(SENKOU_A_RAW, 26) OVER (PARTITION BY SYMBOL ORDER BY PRICE_DATE) AS SENKOU_SPAN_A,
    LAG(SENKOU_B_RAW, 26) OVER (PARTITION BY SYMBOL ORDER BY PRICE_DATE) AS SENKOU_SPAN_B,
    -- Chikou Span: aktueller Schlusskurs, 26 Perioden in die Vergangenheit geplottet
    LEAD(PRICE, 26) OVER (PARTITION BY SYMBOL ORDER BY PRICE_DATE) AS CHIKOU_SPAN
FROM calc
ORDER BY SYMBOL, PRICE_DATE
;
