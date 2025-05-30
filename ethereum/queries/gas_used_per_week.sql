SELECT
	toStartOfWeek(block_timestamp, 1) AS time,
	SUM(receipt_gas_used) AS total_gas_used,
	round(AVG(receipt_gas_used)) AS avg_gas_used,
	quantileExact(0.5)(receipt_gas_used) AS median_gas_used
  -- For approximiation, use: 
  -- quantile(0.5)(receipt_gas_used) AS median_gas_used
FROM transactions
WHERE block_timestamp >= '2015-10-01'
GROUP BY time
ORDER BY time ASC
LIMIT 10