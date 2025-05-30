-- what are the 10 most popular Ethereum tokens (ERC20 contracts), by number of transactions?
SELECT to_address, count() AS tx_count
FROM transactions
WHERE to_address IN (
	SELECT address
	FROM contracts
	WHERE is_erc20 = true
)
GROUP BY to_address
ORDER BY tx_count DESC
LIMIT 5
