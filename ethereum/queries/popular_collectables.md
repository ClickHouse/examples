# What are the 10 most popular Ethereum collectibles (ERC721 contracts), by number of transactions?

Promoted by the [Google Cloud Marketplace](https://console.cloud.google.com/marketplace/details/ethereum/crypto-ethereum-blockchain?project=clickhouse-cloud).

## BigQuery

```sql
SELECT contracts.address, COUNT(1) AS tx_count
FROM `bigquery-public-data.crypto_ethereum.contracts` AS contracts
JOIN `bigquery-public-data.crypto_ethereum.transactions` AS transactions ON (transactions.to_address = contracts.address)
WHERE contracts.is_erc721 = TRUE
GROUP BY contracts.address
ORDER BY tx_count DESC
LIMIT 10
```

## ClickHouse

```sql
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
```

