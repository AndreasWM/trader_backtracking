drop table stock_prices purge;
CREATE TABLE stock_prices (
    symbol      VARCHAR2(20)        NOT NULL,
    price_date  DATE                NOT NULL,
    price       BINARY_DOUBLE,
    high        BINARY_DOUBLE,
    low         BINARY_DOUBLE,
    span_a      BINARY_DOUBLE,
    span_b      BINARY_DOUBLE,
    market_cap  BINARY_DOUBLE,
    CONSTRAINT pk_stock_prices PRIMARY KEY (symbol, price_date)
);
-- CREATE TABLE stock_prices (
--     symbol      VARCHAR2(20)        NOT NULL,
--     price_date  DATE                NOT NULL,
--     price       BINARY_DOUBLE,
--     high        BINARY_DOUBLE,
--     low         BINARY_DOUBLE,
--     market_cap  BINARY_DOUBLE,
--     calendar_day NUMBER GENERATED ALWAYS AS (EXTRACT(DAY FROM price_date)) VIRTUAL,
--     iso_year  NUMBER GENERATED ALWAYS AS (TO_NUMBER(TO_CHAR(price_date, 'IYYY'))) VIRTUAL,
--     calendar_week NUMBER GENERATED ALWAYS AS (TO_NUMBER(TO_CHAR(price_date, 'IW')))   VIRTUAL,
--     calendar_month NUMBER GENERATED ALWAYS AS (EXTRACT(MONTH FROM price_date)) VIRTUAL,
--     calendar_year NUMBER GENERATED ALWAYS AS (EXTRACT(YEAR FROM price_date)) VIRTUAL,
--     CONSTRAINT pk_stock_prices PRIMARY KEY (symbol, price_date)
-- );

-- drop INDEX idx_stock_prices_year;
-- CREATE INDEX idx_stock_prices_year 
-- ON stock_prices (symbol, calendar_year, price_date DESC);

DELETE FROM stock_prices WHERE symbol IN (
    SELECT symbol FROM stock_prices GROUP BY symbol HAVING COUNT(*) < 751
);
commit;
rollback;

drop table depot purge;
CREATE TABLE depot (
    depot_date  DATE                NOT NULL,
    calendar_year NUMBER GENERATED ALWAYS AS (EXTRACT(YEAR FROM depot_date)) VIRTUAL,
    calendar_month NUMBER GENERATED ALWAYS AS (EXTRACT(MONTH FROM depot_date)) VIRTUAL,
    symbol      VARCHAR2(20)        NOT NULL,
    quantity    NUMBER(10,2)        NOT NULL,
    CONSTRAINT pk_depot PRIMARY KEY (depot_date, symbol),
    CONSTRAINT fk_depot_symbol FOREIGN KEY (symbol, depot_date)
        REFERENCES stock_prices (symbol, price_date)
);

drop table account purge;
CREATE TABLE account (
    account_date    DATE            default sysdate NOT NULL,
    calendar_year NUMBER GENERATED ALWAYS AS (EXTRACT(YEAR FROM account_date)) VIRTUAL,
    calendar_month  NUMBER          GENERATED ALWAYS AS (EXTRACT(MONTH FROM account_date)) VIRTUAL,
    balance         BINARY_DOUBLE   NOT NULL,
    CONSTRAINT pk_account PRIMARY KEY (account_date)
);
SET DEFINE OFF;
Insert into "ACCOUNT" (ACCOUNT_DATE,BALANCE) values (to_date('01.01.26','DD.MM.RR'),'10000,0');
commit;

CREATE TABLE market_calendar (
    market_day_no NUMBER(10) CONSTRAINT pk_market_calendar PRIMARY KEY,
    market_date   DATE NOT NULL,
    CONSTRAINT uk_market_calendar_date UNIQUE (market_date)
);

drop table market_calendar purge;
CREATE TABLE market_calendar as
SELECT ROW_NUMBER() OVER (ORDER BY price_date) AS market_day_no,
       price_date market_date
FROM (
    SELECT DISTINCT price_date
    FROM stock_prices
)
ORDER BY price_date
;

SELECT count(*) anz FROM stock_prices
group by symbol
order by anz
;