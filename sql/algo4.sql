with preise as (
  select symbol, price_date datum, price preis, span_a, span_b
    from STOCK_PRICES
  where symbol in ('MU', 'SNDK')
    and PRICE_DATE between to_date('2025.01.01','yyyy.mm.dd') and to_date('2026.07.31','yyyy.mm.dd')
),
vortag as (
  select symbol, datum, preis, lag(preis) over (partition by symbol order by datum) preis_vortag, span_a, span_b
    from preise
),
kaufen as (
  select symbol, datum, preis, 'K' signal
    from vortag
  where preis > span_a and preis > span_b
),
verkaufen as (
  select symbol, datum, preis, 'V' signal
    from vortag
  where preis < span_a or preis < span_b
),
kaufen_verkaufen as (
  select * from kaufen
  union all
  select * from verkaufen
),
streichen_vorbereiten as (
  select symbol, datum, preis, signal,
         lag(signal) over (partition by symbol order by datum) as signal_letztes
   from kaufen_verkaufen
),
streichen as (
  select symbol, datum, preis, signal, rownum zeile
    from streichen_vorbereiten
   where signal_letztes is null or signal <> signal_letztes
),
letzter_preis as (
  select symbol, datum, preis, signal, zeile,
         lag(preis) over (partition by symbol order by zeile) preis_letzter
    from streichen
),
gewinn as (
  select symbol, datum, preis, signal, 0 gewinn_prozent, 0 gewinn_faktor
    from letzter_preis
   where signal = 'K'
  union all
  select symbol, datum, preis, signal, (preis / preis_letzter - 1) * 100 gewinn_prozent, preis / preis_letzter gewinn_faktor
    from letzter_preis
   where signal = 'V'
),
gesamt_gewinn as (
  select symbol, datum, preis, signal, gewinn_prozent, gewinn_faktor
    from gewinn
   where signal = 'K'
  union all
  select symbol, datum, preis, signal, gewinn_prozent, exp(sum(ln(gewinn_faktor)) over (partition by symbol order by datum)) as gewinn_faktor
    from gewinn
   where signal = 'V'
)
select * from gesamt_gewinn
 order by symbol, datum
;

select symbol, datum, preis, market_cap, signal
  from vw_signale
 where datum between to_date('2025.12.01','yyyy.mm.dd') and to_date('2026.07.31','yyyy.mm.dd')
    and symbol in ('SNDK')
  order by symbol, datum
;
select * from STOCK_PRICES
 where symbol = 'BABA'
   and PRICE_DATE between to_date('2026.01.01','yyyy.mm.dd') and to_date('2026.07.31','yyyy.mm.dd')
  order by PRICE_DATE
;

with prices as (
  select /*+ materialize */ symbol, PRICE_DATE datum, PRICE preis, high, low,
         lag(high) over (partition by symbol order by price_date) high_vortag,
         lag(low) over (partition by symbol order by price_date) low_vortag,
         market_cap, span_a, span_b
    from STOCK_PRICES
),
ytd as (
  select p1.symbol, p1.datum, p1.preis, p1.high, p1.high_vortag, p1.low, p1.low_vortag, p1.market_cap, (p1.preis / p2.preis - 1) * 100 as ytd, p1.span_a, p1.span_b
    from prices p1
    join SILVESTER s on s.jahr = extract(year from p1.datum) - 1
    join prices p2 on p2.symbol = p1.symbol
                  and p2.datum = s.last_trading_day
   where p1.market_cap > 50000000000
),
ranked as (
  select ytd.*,
         row_number() over (partition by datum order by ytd desc) as rn
    from ytd
),
top_shares as (
  select symbol, datum, preis, high, high_vortag, low, low_vortag, market_cap, ytd, span_a, span_b
    from ranked
   where rn <= 50
),
kaufen as (
  select symbol, datum, preis, market_cap, 'K' signal, span_a, span_b, high, high_vortag
    from top_shares
  where high > greatest(span_a, span_b) and least(low, low_vortag) <= greatest(span_a, span_b)
),
verkaufen as (
  select symbol, datum, preis, market_cap, 'V' signal, span_a, span_b, low, low_vortag
    from prices
  where symbol in (select symbol from kaufen)
    and low < greatest(span_a, span_b) and low_vortag >= greatest(span_a, span_b)
),
kaufen_verkaufen as (
  select * from kaufen
  union all
  select * from verkaufen
),
streichen as (
  select symbol, datum, preis, market_cap, signal
    from (select symbol, datum, preis, market_cap, signal,
                 lag(signal, 1, 'X') over (partition by symbol order by datum) as signal_letztes
            from kaufen_verkaufen)
   where signal <> signal_letztes
)
select *
  from kaufen
 where datum between to_date('2025.08.01','yyyy.mm.dd') and to_date('2026.07.31','yyyy.mm.dd')
   and symbol in ('SNDK')
  order by symbol, datum
;
