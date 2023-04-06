# Ether Supply By Day

Originally from [Awesome BigQuery views](https://github.com/blockchain-etl/awesome-bigquery-views/blob/master/ethereum/ether-supply-by-day.sql).

## BigQuery

```sql
WITH ether_emitted_by_date  AS (
  SELECT date(block_timestamp) AS date, SUM(value) AS value
  FROM `bigquery-public-data.crypto_ethereum.traces`
  WHERE trace_type IN ('genesis', 'reward')
  GROUP BY DATE(block_timestamp)
)
SELECT date, SUM(value) OVER (ORDER BY date) / POWER(10, 18) AS supply
FROM ether_emitted_by_date
```

## Redshift

```sql
WITH ether_emitted_by_date AS (
  SELECT
    date(block_timestamp) AS date,
    SUM(value) AS value
  FROM
    traces
  WHERE
    trace_type IN ('genesis', 'reward')
  GROUP BY
    DATE(block_timestamp)
)
SELECT
  date,
  SUM(value) OVER (
    ORDER BY
      date ASC ROWS BETWEEN UNBOUNDED PRECEDING
      AND CURRENT ROW
  ) / POWER(10, 18) AS supply
FROM
  ether_emitted_by_date
LIMIT
  10;

```

## ClickHouse

```sql

WITH ether_emitted_by_date AS
	(
    	SELECT
        	date(block_timestamp) AS date,
        	SUM(value) AS value
    	FROM traces
    	WHERE trace_type IN ('genesis', 'reward')
    	GROUP BY DATE(block_timestamp)
	)
SELECT
	date,
	SUM(value) OVER (ORDER BY date ASC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) / POWER(10, 18) AS supply
FROM ether_emitted_by_date
LIMIT 10

ALTER TABLE traces ADD PROJECTION trace_type_projection (
                	SELECT trace_type,
                	toStartOfDay(block_timestamp) as date, sum(value) as value GROUP BY trace_type, date
                	)
ALTER TABLE traces MATERIALIZE PROJECTION trace_type_projection

WITH ether_emitted_by_date AS
	(
    	SELECT
        	date,
        	sum(value) AS value
    	FROM traces
    	WHERE trace_type IN ('genesis', 'reward')
    	GROUP BY toStartOfDay(block_timestamp) AS date
	)
SELECT
	date,
	sum(value) OVER (ORDER BY date ASC) / power(10, 18) AS supply
FROM ether_emitted_by_date

```