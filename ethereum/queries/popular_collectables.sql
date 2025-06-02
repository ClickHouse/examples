SELECT to_address, count() AS tx_count
FROM transactions
WHERE to_address IN (
	SELECT address
	FROM contracts
	WHERE is_erc721 = true
)
GROUP BY to_address
ORDER BY tx_count DESC
LIMIT 5