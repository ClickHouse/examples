-- This is a query that has been modified from a [dune.com visualization](https://dune.com/queries/662981/1231386) that estimates the total market capitalization of Ethereum. Here we use a fixed price of `1577.88` from [CoinDesk](https://www.coindesk.com/price/ethereum/), since our data is a snapshot with a latest date of  `2023-02-14 19:34:59` - adjust based on your latest time.
WITH eth_supply AS
	(
    	SELECT (120529053 - (SUM(eb.base_fee_per_gas * et.receipt_gas_used) / 1000000000000000000.)) + ((COUNT(eb.number) * 1600) / (((24 * 60) * 60) / 12)) AS eth_supply
    	FROM transactions AS et
    	INNER JOIN blocks AS eb ON eb.number = et.block_number
    	WHERE et.block_timestamp >= '2022-09-29'
	)
SELECT (eth_supply * 1577.88) / 1000000000. AS eth_mcap
FROM eth_supply