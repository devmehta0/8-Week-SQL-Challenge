---------------------------------
-- Data Exploration and Cleansing
---------------------------------

-- Update the fresh_segments.interest_metrics table by modifying the month_year column to be a date data type with the start of the month                                                                                                                                                                                                                                                                                                                                                            
SELECT * FROM interest_metrics;

SELECT 
	CONVERT(date,
	'01-' + month_year
	 , 105) 
FROM interest_metrics;

ALTER TABLE interest_metrics
ALTER COLUMN month_year VARCHAR(20);

UPDATE interest_metrics
SET month_year = CONVERT(date,'01-' + month_year, 105) ;

ALTER TABLE interest_metrics
ALTER COLUMN month_year DATE;

-- 2. What is count of records in the fresh_segments.interest_metrics for each month_year value sorted in chronological order (earliest to latest) with the null values appearing first?

SELECT month_year, COUNT(*) cnt
FROM interest_metrics
GROUP BY month_year
ORDER BY month_year;

-- 3. What do you think we should do with these null values in the fresh_segments.interest_metrics
-- we can just drop these values

-- 4. How many interest_id values exist in the fresh_segments.interest_metrics table but not in the fresh_segments.interest_map table? What about the other way around?

SELECT COUNT(im.interest_id) AS cnt FROM interest_metrics im
LEFT JOIN interest_map imp ON imp.id = im.interest_id
WHERE imp.id IS NULL;

-- other way
--(REVERESING THE QUESTION)
SELECT COUNT(imp.id) AS cnt FROM interest_metrics im
RIGHT JOIN interest_map imp ON imp.id = im.interest_id
WHERE im.interest_id IS NULL;

-- 5. Summarise the id values in the fresh_segments.interest_map by its total record count in this table

SELECT COUNT(id) cnt FROM interest_map;

-- 6. What sort of table join should we perform for our analysis and why? 
-- Check your logic by checking the rows where interest_id = 21246 in your joined output and include all columns from fresh_segments.interest_metrics 
-- and all columns from fresh_segments.interest_map except from the id column.

SELECT 
	interest_id,
	interest_name,
	interest_summary,
	created_at,
	last_modified,
	_month,
	_year,
	month_year,
	composition,
	index_value,
	ranking,
	percentile_ranking
FROM interest_map imp
RIGHT JOIN interest_metrics im ON im.interest_id = imp.id
WHERE id = 21246;

-- 7. Are there any records in your joined table where the month_year value is before the created_at value from the fresh_segments.interest_map table?
-- Do you think these values are valid and why?

SELECT COUNT(*) AS cnt 
FROM interest_metrics im
RIGHT JOIN interest_map imp ON im.interest_id = imp.id
WHERE month_year < created_at;

-------------------
--Interest Analysis
-------------------

-- 1. Which interests have been present in all month_year dates in our dataset?

SELECT COUNT(DISTINCT month_year) FROM interest_metrics;

WITH cte
AS
(
	SELECT interest_id, COUNT(DISTINCT month_year) AS distinct_interest
	FROM interest_metrics im
	GROUP BY interest_id
	HAVING COUNT(DISTINCT month_year)=14
)
SELECT 
	cast(interest_name AS varchar(200)) as interest_name
FROM cte
JOIN interest_map imp ON cte.interest_id =imp.id
ORDER BY interest_name;

-- 2. Using this same total_months measure
-- calculate the cumulative percentage of all records starting at 14 months - which total_months value passes the 90% cumulative percentage value?

WITH cte AS (
	SELECT interest_id,
		COUNT(DISTINCT month_year) AS total_month
	FROM interest_metrics
	GROUP BY interest_id
),
innerCte AS (
	SELECT total_month,
		COUNT(*) AS total_id,
		CAST(ROUND(100 * SUM(CAST(COUNT(*) AS NUMERIC(10, 2))) OVER (ORDER BY total_month DESC) 
			/ 
			SUM(COUNT(*)) over(), 2) AS NUMERIC(10, 2)) c_perc
	FROM cte
	GROUP BY total_month
)

SELECT total_month,
	total_id,
	c_perc
FROM innerCte
WHERE c_perc >= 90;
GO

-- 3. If we were to remove all interest_id values which are lower than the total_months value we found in the previous question 
-- - how many total data points would we be removing?

WITH cte
AS
(
	SELECT interest_id,
	COUNT(DISTINCT month_year) AS total_month
	FROM interest_metrics
	GROUP BY interest_id
)
SELECT 
	COUNT(interest_id) AS record_to_delete
FROM cte
where total_month <6;

-- 4. Does this decision make sense to remove these data points from a business perspective? 
-- Use an example where there are all 14 months present to a removed interest example for your arguments 
-- think about what it means to have less months present from a segment perspective.

-- It does make sense, as these data points are less valuable and do not represent any major or effective interests of the users. 
-- So excluding interests let us keep the segmets more targeted and focused to the most popular interests and customers' needs.

SELECT * into #filtered_interest_metrics FROM interest_metrics;

DELETE FROM #filtered_interest_metrics
WHERE interest_id IN
(
	SELECT interest_id
	FROM interest_metrics
	GROUP BY interest_id
	having COUNT(DISTINCT month_year) < 6
)
-- 5. After removing these interests - how many unique interests are there for each month?

SELECT 
	month_year, 
	COUNT(DISTINCT interest_id) AS unique_interests 
FROM #filtered_interest_metrics
WHERE month_year IS NOT NULL
GROUP BY month_year
ORDER BY month_year;

-------------------
-- Segment Analysis
-------------------

-- 1. Using our filtered dataset by removing the interests with less than 6 months worth of data,
-- which are the top 10 and bottom 10 interests which have the largest composition values in any month_year? Only use the maximum composition value for each interest but you must keep the corresponding month_year

WITH cte
AS
(
SELECT month_year,cast(interest_name AS varchar(200)) AS interest_name, SUM(composition) AS composition
FROM #filtered_interest_metrics fim
JOIN interest_map im ON fim.interest_id = im.id
WHERE interest_id IS NOT NULL
GROUP BY month_year, cast(interest_name AS varchar(200))
),
cte_2
AS
(
	SELECT 
		*,
		ROW_NUMBER() OVER(PARTITION BY interest_name ORDER BY composition DESC) AS max_rank,
		ROW_NUMBER() OVER(PARTITION BY interest_name ORDER BY composition ASC) AS min_rank
	FROM cte
)	
select * from
(select top 10 * from cte_2
WHERE min_rank = 1
ORDER BY composition) T1
UNION
SELECT * FROM
(SELECT 
	top 10 *
FROM cte_2
WHERE max_rank = 1 
ORDER BY composition DESC) T;

-- 2. Which 5 interests had the lowest average ranking value?

SELECT * FROM #filtered_interest_metrics;

SELECT TOP 5 cast(interest_name AS varchar(200)) as interest_name, AVG(ranking) as ranking 
FROM #filtered_interest_metrics fim 
JOIN interest_map im ON fim.interest_id = im.id
GROUP BY cast(interest_name AS varchar(200))  
order by ranking DESC;

-- 3. Which 5 interests had the largest standard deviation in their percentile_ranking value?

WITH cte
AS
(
	SELECT 
		cast(interest_name AS varchar(200)) AS interest_name, 
		CAST(ROUND(STDEV(CAST(percentile_ranking AS NUMERIC(10, 2))), 2) AS NUMERIC(10, 2)) AS std_percentile_ranking
	FROM #filtered_interest_metrics fim
	JOIN interest_map im ON fim.interest_id = im.id
	GROUP BY cast(interest_name AS varchar(200))
)
SELECT TOP 5 *
INTO #temp2
FROM cte
ORDER BY std_percentile_ranking DESC;

SELECT * FROM #temp2;

-- 4. For the 5 interests found in the previous question 
-- what was minimum and maximum percentile_ranking values for each interest and its corresponding year_month value? 
-- Can you describe what is happening for these 5 interests?
WITH cte
AS
(
	SELECT 
		month_year,
		cast(interest_name AS varchar(200)) as interest_name,
		percentile_ranking,
		RANK() OVER(PARTITION BY interest_id ORDER BY percentile_ranking) min,
		RANK() OVER(PARTITION BY interest_id ORDER BY percentile_ranking DESC) max
	FROM #filtered_interest_metrics fim
	JOIN interest_map im ON fim.interest_id = im.id
	WHERE cast(interest_name AS varchar(200)) IN (select interest_name from #temp2)
)
SELECT 
	month_year,
	interest_name,
	percentile_ranking
FROM cte
WHERE min =1 or max =1
ORDER BY interest_name, percentile_ranking DESC;

-----------------
-- Index Analysis
-----------------
drop table #temp3;
SELECT *,
	CAST(composition/index_value AS NUMERIC(5,2)) AS avg_composition
INTO #temp3
FROM interest_metrics
WHERE interest_id IS NOT NULL;

DROP TABLE IF EXISTS  #temp4;
WITH cte
AS
(
	SELECT *,
		ROW_NUMBER() OVER(PARTITION BY month_year ORDER BY avg_composition DESC) AS avg_comp_monthly_rank
	FROM #temp3 T
	JOIN interest_map im ON T.interest_id = im.id

)
SELECT month_year,
	interest_name,
	avg_composition,
	avg_comp_monthly_rank
	INTO #temp4
FROM cte
WHERE avg_comp_monthly_rank<=10 AND month_year IS NOT NULL 
ORDER BY month_year, avg_composition DESC;

SELECT month_year,
	interest_name,
	avg_composition FROM #temp4;

select * from #temp4;

-- 2. For all of these top 10 interests - which interest appears the most often?

SELECT TOP 1 cast(interest_name AS varchar(200)), COUNT(*) AS cnt
FROM #temp4
GROUP BY cast(interest_name AS varchar(200))
ORDER BY cnt DESC;

-- 3. What is the average of the average composition for the top 10 interests for each month?

SELECT month_year, avg(avg_composition) AS _avg
FROM #temp4
GROUP BY month_year
ORDER BY month_year;

-- 4. What is the 3 month rolling average of the max average composition value from September 2018 to August 2019 and include the previous top ranking interests in the same output shown below.

SELECT month_year, MAX(avg_composition) AS monthly_max,
AVG(avg_composition) OVER(ORDER BY month_year), 2)
FROM #temp3
WHERE month_year IS NOT NULL AND month_year BETWEEN '2018-09-01' AND '2019-08-01'
GROUP BY month_year
ORDER BY month_year;

WITH cte
AS (SELECT 
	month_year,
	interest_id,
	avg_composition AS max_index_composition,
	CAST(ROUND(AVG(avg_composition) OVER(ORDER BY month_year), 2) AS NUMERIC(10, 2)) "3_month_moving_avg",
	CONCAT(LAG(interest_id) OVER(ORDER BY month_year), ' : ', LAG(avg_composition) OVER(ORDER BY month_year)) "1_month_ago",
	CONCAT(LAG(interest_id, 2) OVER(ORDER BY month_year), ' : ', LAG(avg_composition, 2) OVER(ORDER BY month_year)) "2_month_ago"
FROM #temp3)

SELECT * 
FROM cte
WHERE month_year > '2018-08-01';
GO

WITH cte
AS
(
	Select *,
		CAST(AVG(avg_composition) OVER(ORDER BY month_year ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS NUMERIC(5,2)) AS '3_month_moving_avg',
		CONCAT(LAG(interest_name,1) OVER(ORDER BY month_year), ': ', LAG(avg_composition,1) OVER(ORDER BY month_year)) AS '1_month_ago',	   
		CONCAT(LAG(interest_name,2) OVER(ORDER BY month_year), ': ', LAG(avg_composition,2) OVER(ORDER BY month_year)) AS '2_months_ago'
	from #temp4
	where avg_comp_monthly_rank = 1
)
SELECT 
	month_year,
	interest_name,
	avg_composition AS max_index_composition,
	"3_month_moving_avg",
	"1_month_ago",
	"2_months_ago"
FROM cte
WHERE month_year >= '2018-09-01';