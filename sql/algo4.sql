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
 where datum between to_date('2026.01.01','yyyy.mm.dd') and to_date('2026.07.31','yyyy.mm.dd')
  --  and symbol in ('SNDK')
  order by symbol, datum
;
