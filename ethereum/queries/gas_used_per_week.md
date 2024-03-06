# Ethereum Gas Used Per Week

This week has been adapted from this Dune [visualization](https://dune.com/queries/892365/1559703). For an explanation of Gas see [here](https://ethereum.org/en/developers/docs/gas/). We modify the query to use `receipt_gas_used` instead of `gas_used`. In our provisioned Redshift cluster this query executes in 66.3secs.

## Redshift

```sql
SELECT
  date_trunc('week', block_timestamp) AS time,
  SUM(receipt_gas_used) AS total_gas_used,
  AVG(receipt_gas_used) AS avg_gas_used,
  percentile_cont(.5) within GROUP (
    ORDER BY
      receipt_gas_used
  ) AS median_gas_used
FROM
  transactions
WHERE
  block_timestamp >= '2015-10-01'
GROUP BY
  time
ORDER BY
  time ASC
LIMIT
  10;
```

## ClickHouse

```sql
SELECT
	toStartOfWeek(block_timestamp, 1) AS time,
	SUM(receipt_gas_used) AS total_gas_used,
	round(AVG(receipt_gas_used)) AS avg_gas_used,
	quantileExact(0.5)(receipt_gas_used) AS median_gas_used
FROM transactions
WHERE block_timestamp >= '2015-10-01'
GROUP BY time
ORDER BY time ASC
LIMIT 10

```

With approximation:

```sql
SELECT
	toStartOfWeek(block_timestamp,1) AS time,
	SUM(receipt_gas_used) AS total_gas_used,
	round(AVG(receipt_gas_used)) AS avg_gas_used,
	quantile(0.5)(receipt_gas_used) AS median_gas_used
FROM transactions
WHERE block_timestamp >= '2015-10-01'
GROUP BY time
ORDER BY time ASC
LIMIT 10
```