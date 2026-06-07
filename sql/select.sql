select * from vw_invest
;
SELECT COALESCE(
  (SELECT balance 
    FROM account
    ORDER BY account_date DESC
    FETCH FIRST 1 ROWS ONLY),
  10000
) AS balance
FROM dual
;
select calendar_year, calendar_month, sum(total_price) as total_investment
  from vw_invest
 group by calendar_year, calendar_month
 order by calendar_year, calendar_month
;
select * from depot
;
select calendar_year, calendar_month
  from account
 order by calendar_year, calendar_month, symbol
;
with count_of_balances as (
  select count(*) number_of_balances
    from account
),
new_investment_date as (
  select calendar_year, calendar_month
    from vw_invest
  group by calendar_year, calendar_month
  order by calendar_year, calendar_month
  fetch first 1 rows only
)
select calendar_year, calendar_month
  from new_investment_date
 where (select number_of_balances from count_of_balances) = 0
union all
select calendar_year, calendar_month
from account
;