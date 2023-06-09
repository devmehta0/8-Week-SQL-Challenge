-- setting schema 
SET search_path = foodie_fi;

-- A. Customer Journey

-- Based off the 8 sample customers provided in the sample from the subscriptions table, 
-- write a brief description about each customer’s onboarding journey.
-- Try to keep it as short as possible - you may also want to run some sort of join to make your explanations a bit easier!

SELECT * 
FROM subscriptions
JOIN plans USING(plan_id)
WHERE customer_id < 9;
-- FINDINGS
-- CUSTOMER 1: first started as trial user on 2020-08-01 and later switch to basic monthly after 7 days on 2020-08-08 and currently using the same plan.

-- CUSTOMER 2:  first started as trial user on 2020-08-01 and later switch to pro annual after 7 days on 2020-08-08 and currently using the same plan.


-- B. Data Analysis Questions

-- B1. How many customers has Foodie-Fi ever had?

SELECT COUNT(DISTINCT customer_id)
FROM subscriptions;

-- B2. What is the monthly distribution of trial plan start_date values for our dataset - use the start of the month as the group by value

SELECT * FROM plans;

SELECT EXTRACT(MONTH FROM start_date) AS month, COUNT(customer_id) AS trail_plans
FROM subscriptions
WHERE plan_id = 0
GROUP BY EXTRACT(MONTH FROM start_date)
ORDER BY month;

-- B3. What plan start_date values occur after the year 2020 for our dataset? Show the breakdown by count of events for each plan_name

SELECT plan_name, count(*)
FROM subscriptions
JOIN plans USING(plan_id)
WHERE EXTRACT(YEAR FROM start_date) > 2020
GROUP BY plan_name
ORDER BY count DESC;

-- B4. What is the customer count and percentage of customers who have churned rounded to 1 decimal place?

SELECT * FROM subscriptions;

WITH cte
AS
(
	SELECT
		(SELECT COUNT(DISTINCT customer_id) :: numeric FROM subscriptions)AS total_customer,
		COUNT(*):: numeric AS churn 
	FROM subscriptions
	WHERE plan_id = 4
)
SELECT total_customer, ROUND(churn*100/total_customer,1) AS churn_perc 	
FROM cte

-- B5. How many customers have churned straight after their initial free trial
-- - what percentage is this rounded to the nearest whole number?

WITH cte
AS
(
	SELECT 
		customer_id,
		plan_id,
		LAG(plan_id, 1) OVER(PARTITION BY customer_id ORDER BY start_date) l,
		ROW_NUMBER() OVER(PARTITION BY customer_id ORDER BY start_date) rn
	FROM subscriptions
)

SELECT 
	ROUND(COUNT(customer_id) * 100.0 / (SELECT COUNT(DISTINCT customer_id) FROM subscriptions), 2) AS Perc
FROM cte
WHERE 
	l = 0 and
	rn = 2 and 
	plan_id = 4;

-- 6. What is the number and percentage of customer plans after their initial free trial?

-- ASSUMPTIONS: only considering the next immediate plan customer opted after free trial

-- SELECT 
-- 	plan_id,
-- 	count(customer_id)
-- FROM 
-- 	subscriptions
-- GROUP BY plan_id

EXPLAIN ANALYZE
WITH cte
AS
(
	SELECT 
		customer_id,
		plan_id,
		ROW_NUMBER() OVER(PARTITION BY customer_id ORDER BY start_date) rn
	FROM 
		subscriptions
)
SELECT 
	plan_id,
	COUNT(*),
	ROUND(COUNT(*) * 100.0/(SELECT COUNT(DISTINCT customer_id) FROM subscriptions),2) AS percent
FROM cte
WHERE rn=2
GROUP BY plan_id;

-- bothapproach are almost same just trying to optimize the performance of query.
EXPLAIN ANALYZE
WITH cte
AS
(
	SELECT 
		customer_id,
		plan_id,
		ROW_NUMBER() OVER(PARTITION BY customer_id ORDER BY start_date) rn
	FROM 
		subscriptions
),
cte_2
AS
(
	SELECT 
		plan_id,
		COUNT(*) AS count
	FROM cte
	WHERE rn=2
	GROUP BY plan_id
)
SELECT plan_id, count, ROUND(count * 100.0/(SELECT COUNT(DISTINCT customer_id) FROM subscriptions),2) AS percent
FROM cte_2;

-- 7. What is the customer count and percentage breakdown of all 5 plan_name values at 2020-12-31?

-- My approach: working smartly BUT just ignoring one edge case, for ex: where the customer subscribe for any period of time and 
-- churn it just before 2020-12-31. so my query will ignore that plan and customer but it will return the actual subscribed plan:(

WITH cte
AS
(SELECT 
	customer_id,
	plan_id
FROM
	subscriptions
WHERE 
	plan_id NOT IN (0,4) AND start_date < '2020-12-31'
UNION 
SELECT 
	customer_id,
	plan_id
FROM
	subscriptions
WHERE
	plan_id = 0 AND start_date BETWEEN '2020-12-25' AND '2020-12-31'
)
SELECT 
	plan_id,
	COUNT(DISTINCT customer_id) as count,
	ROUND(COUNT(DISTINCT customer_id) * 100.0/ (select COUNT(customer_id) from cte),2) as percent
FROM
	cte
GROUP BY 
	plan_id;
	
-- 8. How many customers have upgraded to an annual plan in 2020?

WITH cte
AS
(
	SELECT 
		customer_id,
		plan_id,
		start_date,
		ROW_NUMBER() OVER(PARTITION BY customer_id ORDER BY start_date) rn
	FROM 
		subscriptions
)
select count(DISTINCT customer_id)
from cte
WHERE rn > 1 AND plan_id = 3 AND EXTRACT(YEAR FROM start_date) = 2020

-- 9. How many days on average does it take for a customer to an annual plan from the day they join Foodie-Fi?

WITH cte
AS
(	
	SELECT 
		*,
		LAST_VALUE(start_date) OVER(PARTITION BY customer_id ORDER BY plan_id)	
		- FIRST_VALUE(start_date) OVER(PARTITION BY customer_id ORDER BY plan_id) AS difference	
	FROM subscriptions
	WHERE plan_id IN (0,3)
	order by customer_id
)
SELECT ROUND(AVG(difference))
FROM cte
WHERE difference>0

-- 10. Can you further breakdown this average value into 30 day periods (i.e. 0-30 days, 31-60 days etc)

-- INITIAL APPROACH
-- WITH cte
-- AS
-- (	
-- 	SELECT 
-- 		*,
-- 		LAST_VALUE(start_date) OVER(PARTITION BY customer_id ORDER BY plan_id)	
-- 		- FIRST_VALUE(start_date) OVER(PARTITION BY customer_id ORDER BY plan_id) AS difference	
-- 	FROM subscriptions
-- 	WHERE plan_id IN (0,3)
-- 	order by customer_id
-- ),
-- cte_2 
-- AS
-- (
-- 	SELECT 
-- 		generate_series(min(difference), max(difference), 30) as r_from
-- 	FROM cte
-- 	WHERE difference>0
-- ),
-- range
-- AS
-- (
-- 	SELECT 
-- 		r_from,
-- 		LEAD(r_from, 1) over() -1 as r_to
-- 	FROM cte_2
-- )
-- SELECT 
-- 	r_from,
-- 	r_to,
-- 	(SELECT round(avg(difference)) from cte WHERE difference BETWEEN r_from AND r_to) AS average_days,
-- 	(SELECT count(difference) from cte WHERE difference BETWEEN r_from AND r_to) AS average_days
-- FROM
-- 	range

-- range 0 to 30
WITH cte
AS
(	
	SELECT 
		*,
		LAST_VALUE(start_date) OVER(PARTITION BY customer_id ORDER BY plan_id)	
		- FIRST_VALUE(start_date) OVER(PARTITION BY customer_id ORDER BY plan_id) AS difference	
	FROM subscriptions
	WHERE plan_id IN (0,3)
	order by customer_id
),
series 
AS
(
	SELECT 
		generate_series(0, MAX(difference)+30, 30) as r_from
	FROM cte
	WHERE difference>0
),
range
AS
(
	SELECT 
		r_from,
		LEAD(r_from, 1) over() -1 as r_to
	FROM series
)
SELECT 
	r_from,
	r_to,
	(SELECT round(avg(difference)) from cte WHERE (difference BETWEEN r_from AND r_to) AND difference!=0)  AS average_days,
	(SELECT count(difference) from cte WHERE difference BETWEEN r_from AND r_to AND difference!=0) AS customer_count
FROM
	range
WHERE 
	r_to IS NOT NULL


-- 11. How many customers downgraded from a pro monthly to a basic monthly plan in 2020?

WITH cte
AS
(
	SELECT 
		customer_id,
		plan_id,
		LEAD(plan_id, 1) OVER(PARTITION BY customer_id ORDER BY start_date) l
	FROM subscriptions
	WHERE plan_id = 3
)
SELECT count(*)
FROM cte
WHERE l=2;

-- C. Challenge Payment Question
-- GITHUB's
SELECT
  customer_id,
  plan_id,
  plan_name,
  payment_date ::date :: varchar,
  CASE
    WHEN LAG(plan_id) OVER (
      PARTITION BY customer_id
      ORDER BY
        plan_id
    ) != plan_id
    AND DATE_PART(
      'day',
      payment_date - LAG(payment_date) OVER (
        PARTITION BY customer_id
        ORDER BY
          plan_id
      )
    ) < 30 THEN amount - LAG(amount) OVER (
      PARTITION BY customer_id
      ORDER BY
        plan_id
    )
    ELSE amount
  END AS amount,
  RANK() OVER(
    PARTITION BY customer_id
    ORDER BY
      payment_date
  ) AS payment_order 
  
INTO TEMP TABLE payments
FROM
(SELECT
      customer_id,
      s.plan_id,
      plan_name,
      generate_series(
        start_date,
        CASE
          WHEN s.plan_id = 3 THEN start_date
          WHEN s.plan_id = 4 THEN NULL
          WHEN LEAD(start_date) OVER (PARTITION BY customer_id ORDER BY start_date) IS NOT NULL 
		  	THEN LEAD(start_date) OVER (PARTITION BY customer_id ORDER BY start_date)
          ELSE '2020-12-31' :: date
        END,
        '1 month' + '1 second' :: interval
      ) AS payment_date,
      price AS amount
    FROM
      subscriptions AS s
      JOIN plans AS p ON s.plan_id = p.plan_id
    WHERE
      s.plan_id != 0
      AND start_date < '2021-01-01' :: date
    GROUP BY
      customer_id,
      s.plan_id,
      plan_name,
      start_date,
      price
) t
ORDER BY
  customer_id

-- D. Outside The Box Questions

-- 1. How would you calculate the rate of growth for Foodie-Fi?

WITH cte
AS
(
	SELECT
		*,
		EXTRACT(MONTH FROM start_date) as month, 
		EXTRACT(YEAR FROM start_date) AS year
	FROM subscriptions
	WHERE plan_id != 4
)
SELECT
	year,
	month,
	count(customer_id) as current_number_of_customers,
	LAG(count(customer_id), 1) OVER(ORDER BY year, month) past_number_of_customers,
	(100 * (COUNT(customer_id) - LAG(COUNT(customer_id), 1) OVER(ORDER BY year, month)) / LAG(COUNT(customer_id), 1) over (
  ORDER BY
	year, month)
)|| '%' AS growth
from cte
GROUP BY year, month
order by year, month;

	
	