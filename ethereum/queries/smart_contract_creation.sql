-- adapted from https://dune.com/queries/649454/1207086

SELECT
	toStartOfWeek(block_timestamp, 1) AS time,
	count() AS created_contracts,
	sum(created_contracts) OVER (ORDER BY time ASC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_created_contracts
FROM traces
WHERE trace_type = 'create'
GROUP BY time
ORDER BY time ASC
LIMIT 10