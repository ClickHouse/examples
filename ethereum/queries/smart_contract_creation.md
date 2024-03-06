## Smart Contract Creation by Week

We adapt this query from a [dune.com visualization](https://dune.com/queries/649454/1207086). We remove the `now()` restriction since our data has a fixed upper bound. Due to Redshift not supporting the window RANGE function, we are also forced to modify the query slightly to compute the cumulative sum. ClickHouse runs this query in 76ms vs Redshift in 250ms, despite both tables being ordered by `trace_type`.

## Redshift

```sql
SELECT
  date_trunc('week', block_timestamp) AS time,
  COUNT(*) AS created_contracts,
  sum(created_contracts) OVER (
	ORDER BY
  	time rows UNBOUNDED PRECEDING
  ) AS cum_created_contracts
from
  traces
WHERE
  trace_type = 'create'
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
	count() AS created_contracts,
	sum(created_contracts) OVER (ORDER BY time ASC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_created_contracts
FROM traces
WHERE trace_type = 'create'
GROUP BY time
ORDER BY time ASC
LIMIT 10
```

