------------------------------------------------------------------------------
-- ICHIMOKU-RANG-ROTATIONS-SIMULATION
-- Reine DB-Simulation ohne Broker-Anbindung.
--
-- Konzept:
--   1) Nur Aktien, deren Kurs ueber der Ichimoku-Wolke liegt (PRICE > SENKOU_SPAN_A
--      und PRICE > SENKOU_SPAN_B), werden ueberhaupt betrachtet.
--   2) Unter diesen wird taeglich nach YTD-Performance (Basis: Kurs am 31.12.2025)
--      ein Rang vergeben.
--   3) Am Starttag wird ein Kapitalbetrag gleichmaessig auf die TOP-N (Default 10)
--      Aktien verteilt.
--   4) An jedem weiteren Handelstag wird geprueft:
--        - Ist eine gehaltene Aktie aus der Wolke gefallen ODER nicht mehr in den
--          TOP-N?  -> verkaufen.
--        - Sind Slots frei (weil verkauft wurde)? -> mit den best-gerankten,
--          noch nicht gehaltenen Aktien neu gleichmaessig auffuellen.
--   5) Der Gesamtwert (Cash + Marktwert aller offenen Positionen) wird taeglich
--      fortgeschrieben.
------------------------------------------------------------------------------


------------------------------------------------------------------------------
-- 1) VIEW: taeglicher Wolken-Filter + YTD-Rang
--    (Verallgemeinerung Ihrer CTE "perf" - jetzt fuer ALLE Symbole/Tage)
------------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_daily_rank AS
WITH baseline AS (
    SELECT symbol, price AS base_price
    FROM   tmp_ichimoku
    WHERE  price_date = DATE '2025-12-31'
),
perf AS (
    SELECT t.symbol,
           t.price_date,
           t.price,
           (t.price / b.price - 1) * 100 AS perf_pct
    FROM   tmp_ichimoku t
    -- JOIN   baseline b ON b.symbol = t.symbol
    join tmp_ICHIMOKU b on b.symbol = t.symbol
                        and b.PRICE_DATE = add_months(t.PRICE_DATE, -12)
    where  t.price > t.senkou_span_a
    AND    t.price > t.senkou_span_b
)
SELECT symbol,
       price_date,
       price,
       perf_pct,
       ROW_NUMBER() OVER (PARTITION BY price_date ORDER BY perf_pct DESC) AS rnk
FROM perf;
/


------------------------------------------------------------------------------
-- 2) TABELLEN fuer die Simulation
------------------------------------------------------------------------------
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE port_positions PURGE';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -942 THEN RAISE; END IF;  -- -942 = Tabelle existiert nicht -> ignorieren
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE port_cash PURGE';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -942 THEN RAISE; END IF;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE port_value_history PURGE';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

CREATE TABLE port_positions (
    position_id  NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    symbol       VARCHAR2(20)  NOT NULL,
    entry_date   DATE          NOT NULL,
    entry_price  BINARY_DOUBLE NOT NULL,
    shares       BINARY_DOUBLE NOT NULL,
    exit_date    DATE,
    exit_price   BINARY_DOUBLE,
    status       VARCHAR2(10) DEFAULT 'OPEN' NOT NULL
                 CHECK (status IN ('OPEN','CLOSED'))
);

CREATE TABLE port_cash (
    cash_date   DATE PRIMARY KEY,
    cash_amount BINARY_DOUBLE NOT NULL
);

CREATE TABLE port_value_history (
    value_date      DATE PRIMARY KEY,
    cash_amount     BINARY_DOUBLE,
    positions_value BINARY_DOUBLE,
    total_value     BINARY_DOUBLE,
    num_positions   NUMBER
);


------------------------------------------------------------------------------
-- 3) PACKAGE: eigentliche Simulationslogik
------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_ichimoku_sim AS

    PROCEDURE run_simulation(
        p_start_date    DATE,
        p_end_date      DATE,
        p_capital       BINARY_DOUBLE,
        p_max_positions NUMBER DEFAULT 10
    );

END pkg_ichimoku_sim;
/


CREATE OR REPLACE PACKAGE BODY pkg_ichimoku_sim AS

    ----------------------------------------------------------------------
    -- Kurs eines Symbols an einem Tag (aus TMP_ICHIMOKU)
    ----------------------------------------------------------------------
    FUNCTION get_price(p_symbol VARCHAR2, p_date DATE) RETURN BINARY_DOUBLE IS
        v_price BINARY_DOUBLE;
    BEGIN
        SELECT price INTO v_price
        FROM   tmp_ichimoku
        WHERE  symbol = p_symbol
        AND    price_date = p_date;
        RETURN v_price;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN NULL;  -- z.B. Handelsaussetzung / keine Notierung
    END get_price;

    ----------------------------------------------------------------------
    -- Rang eines Symbols an einem Tag (NULL = nicht ueber der Wolke /
    -- nicht im Datenbestand)
    ----------------------------------------------------------------------
    FUNCTION get_rank(p_symbol VARCHAR2, p_date DATE) RETURN NUMBER IS
        v_rnk NUMBER;
    BEGIN
        SELECT rnk INTO v_rnk
        FROM   v_daily_rank
        WHERE  symbol = p_symbol
        AND    price_date = p_date;
        RETURN v_rnk;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN NULL;
    END get_rank;

    ----------------------------------------------------------------------
    -- letzter bekannter Cash-Stand vor/inklusive p_date
    ----------------------------------------------------------------------
    FUNCTION get_cash(p_date DATE) RETURN BINARY_DOUBLE IS
        v_cash BINARY_DOUBLE;
    BEGIN
        SELECT cash_amount INTO v_cash
        FROM   port_cash
        WHERE  cash_date = (SELECT MAX(cash_date)
                             FROM   port_cash
                             WHERE  cash_date <= p_date);
        RETURN v_cash;
    END get_cash;

    ----------------------------------------------------------------------
    -- Position schliessen (verkaufen)
    ----------------------------------------------------------------------
    PROCEDURE close_position(p_position_id NUMBER, p_date DATE, p_price BINARY_DOUBLE) IS
    BEGIN
        UPDATE port_positions
        SET    exit_date  = p_date,
               exit_price = p_price,
               status     = 'CLOSED'
        WHERE  position_id = p_position_id;
    END close_position;

    ----------------------------------------------------------------------
    -- Position eroeffnen (kaufen)
    ----------------------------------------------------------------------
    PROCEDURE open_position(p_symbol VARCHAR2, p_date DATE, p_price BINARY_DOUBLE,
                             p_invest_amount BINARY_DOUBLE) IS
    BEGIN
        INSERT INTO port_positions(symbol, entry_date, entry_price, shares, status)
        VALUES (p_symbol, p_date, p_price, p_invest_amount / p_price, 'OPEN');
    END open_position;

    ----------------------------------------------------------------------
    -- Ein Handelstag: pruefen / verkaufen / neu kaufen / Cash fortschreiben
    ----------------------------------------------------------------------
    PROCEDURE rebalance_day(p_date DATE, p_max_positions NUMBER) IS
        v_cash            BINARY_DOUBLE;
        v_rnk             NUMBER;
        v_price           BINARY_DOUBLE;
        v_free_slots      NUMBER;
        v_candidate_count NUMBER;
        v_buy_count       NUMBER;
        v_invest_each     BINARY_DOUBLE;
    BEGIN
        v_cash := get_cash(p_date - 1);

        -- (a) offene Positionen pruefen: raus aus Wolke oder Rang zu schlecht -> verkaufen
        FOR pos IN (SELECT position_id, symbol, shares
                    FROM   port_positions
                    WHERE  status = 'OPEN')
        LOOP
            v_rnk := get_rank(pos.symbol, p_date);

            IF v_rnk IS NULL OR v_rnk > p_max_positions THEN
                v_price := get_price(pos.symbol, p_date);
                IF v_price IS NOT NULL THEN
                    close_position(pos.position_id, p_date, v_price);
                    v_cash := v_cash + pos.shares * v_price;
                END IF;
                -- Falls v_price NULL (keine Notierung mehr): Position bleibt
                -- vorerst offen, wird am naechsten verfuegbaren Handelstag geprueft.
            END IF;
        END LOOP;

        -- (b) freie Slots ermitteln
        SELECT p_max_positions - COUNT(*) INTO v_free_slots
        FROM   port_positions
        WHERE  status = 'OPEN';

        IF v_free_slots > 0 THEN
            SELECT COUNT(*) INTO v_candidate_count
            FROM   v_daily_rank r
            WHERE  r.price_date = p_date
            AND    r.rnk <= p_max_positions
            AND    NOT EXISTS (SELECT 1 FROM port_positions pp
                               WHERE pp.symbol = r.symbol AND pp.status = 'OPEN');

            v_buy_count := LEAST(v_free_slots, v_candidate_count);

            IF v_buy_count > 0 THEN
                v_invest_each := v_cash / v_buy_count;

                FOR cand IN (SELECT symbol, price
                             FROM   v_daily_rank r
                             WHERE  r.price_date = p_date
                             AND    r.rnk <= p_max_positions
                             AND    NOT EXISTS (SELECT 1 FROM port_positions pp
                                                WHERE pp.symbol = r.symbol AND pp.status = 'OPEN')
                             ORDER BY r.rnk
                             FETCH FIRST v_buy_count ROWS ONLY)
                LOOP
                    open_position(cand.symbol, p_date, cand.price, v_invest_each);
                    v_cash := v_cash - v_invest_each;
                END LOOP;
            END IF;
        END IF;

        INSERT INTO port_cash(cash_date, cash_amount) VALUES (p_date, v_cash);
    END rebalance_day;

    ----------------------------------------------------------------------
    -- Gesamtwert (Cash + Marktwert offener Positionen) fuer einen Tag
    ----------------------------------------------------------------------
    PROCEDURE mark_to_market(p_date DATE) IS
        v_cash      BINARY_DOUBLE;
        v_pos_value BINARY_DOUBLE;
        v_count     NUMBER;
    BEGIN
        SELECT cash_amount INTO v_cash
        FROM   port_cash WHERE cash_date = p_date;

        SELECT NVL(SUM(pp.shares * ti.price), 0), COUNT(*)
        INTO   v_pos_value, v_count
        FROM   port_positions pp
        JOIN   tmp_ichimoku ti
               ON ti.symbol = pp.symbol AND ti.price_date = p_date
        WHERE  pp.status = 'OPEN';

        INSERT INTO port_value_history(value_date, cash_amount, positions_value,
                                        total_value, num_positions)
        VALUES (p_date, v_cash, v_pos_value, v_cash + v_pos_value, v_count);
    END mark_to_market;

    ----------------------------------------------------------------------
    -- Hauptprozedur: Simulation ueber den gesamten Zeitraum laufen lassen
    ----------------------------------------------------------------------
    PROCEDURE run_simulation(
        p_start_date    DATE,
        p_end_date      DATE,
        p_capital       BINARY_DOUBLE,
        p_max_positions NUMBER DEFAULT 10
    ) IS
    BEGIN
        DELETE FROM port_positions;
        DELETE FROM port_cash;
        DELETE FROM port_value_history;

        -- Startkapital als Cash-Stand VOR dem ersten Handelstag verbuchen
        INSERT INTO port_cash(cash_date, cash_amount)
        VALUES (p_start_date - 1, p_capital);

        FOR d IN (SELECT market_date
                  FROM   market_calendar
                  WHERE  market_date BETWEEN p_start_date AND p_end_date
                  ORDER  BY market_date)
        LOOP
            rebalance_day(d.market_date, p_max_positions);
            mark_to_market(d.market_date);
        END LOOP;

        COMMIT;
    END run_simulation;

END pkg_ichimoku_sim;
/


------------------------------------------------------------------------------
-- 4) BEISPIELAUFRUF
------------------------------------------------------------------------------
-- BEGIN
--     pkg_ichimoku_sim.run_simulation(
--         p_start_date    => DATE '2026-01-02',
--         p_end_date      => DATE '2026-06-30',
--         p_capital       => 100000,
--         p_max_positions => 10
--     );
-- END;
-- /


------------------------------------------------------------------------------
-- 5) KONTROLL-ABFRAGEN
------------------------------------------------------------------------------

-- Wertentwicklung des Gesamtportfolios
-- SELECT value_date, cash_amount, positions_value, total_value, num_positions
-- FROM   port_value_history
-- ORDER BY value_date;

-- Aktuell offene Positionen mit aktuellem Marktwert
-- SELECT pp.symbol, pp.entry_date, pp.entry_price, pp.shares,
--        (pp.shares * ti.price) AS current_value
-- FROM   port_positions pp
-- JOIN   tmp_ichimoku ti
--        ON ti.symbol = pp.symbol
--        AND ti.price_date = (SELECT MAX(value_date) FROM port_value_history)
-- WHERE  pp.status = 'OPEN'
-- ORDER BY current_value DESC;

-- Vollstaendiges Trade-Log
-- SELECT * FROM port_positions ORDER BY entry_date, symbol;