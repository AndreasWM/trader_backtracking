------------------------------------------------------------------------------
-- 5) KONTROLL-ABFRAGEN
------------------------------------------------------------------------------

-- Wertentwicklung des Gesamtportfolios
SELECT value_date, cash_amount, positions_value, total_value, num_positions
FROM   port_value_history
ORDER BY value_date;

-- Aktuell offene Positionen mit aktuellem Marktwert
SELECT pp.symbol, pp.entry_date, pp.entry_price, pp.shares,
       (pp.shares * ti.price) AS current_value
FROM   port_positions pp
JOIN   tmp_ichimoku ti
       ON ti.symbol = pp.symbol
       AND ti.price_date = (SELECT MAX(value_date) FROM port_value_history)
WHERE  pp.status = 'OPEN'
ORDER BY current_value DESC;

-- Vollstaendiges Trade-Log
SELECT * FROM port_positions ORDER BY entry_date, symbol;