-- Extracted from the [most popular notebook](https://www.kaggle.com/code/mrisdal/visualizing-average-ether-costs-over-time) for this dataset on Kaggle.
SELECT
	SUM(value / POWER(10, 18)) AS sum_tx_ether,
	AVG(gas_price * (receipt_gas_used / POWER(10, 18))) AS avg_tx_gas_cost,
	toStartOfDay(block_timestamp) AS tx_date
FROM transactions
WHERE (receipt_status = 1) AND (value > 0) AND (block_timestamp > '2018-01-01') AND (block_timestamp <= '2018-12-31')
GROUP BY tx_date
ORDER BY tx_date ASC