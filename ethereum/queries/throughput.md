# Ethereum Throughput

Originally from [Awesome BigQuery Views](https://github.com/blockchain-etl/awesome-bigquery-views#transaction-throughput-comparison) and [Comparing Transaction Throughputs for 8 blockchains in Google BigQuery with Google Data Studio](https://evgemedvedev.medium.com/comparing-transaction-throughputs-for-8-blockchains-in-google-bigquery-with-google-data-studio-edbabb75b7f1)

## BigQuery

```
SELECT 'ethereum' AS chain, count(*) / (24 * 60 * 60 / count(*) OVER (PARTITION BY DATE(block_timestamp))) AS throughput, block_timestamp AS time
    FROM `bigquery-public-data.crypto_ethereum.transactions` AS transactions
    GROUP BY transactions.block_number, transactions.block_timestamp
    ORDER BY throughput DESC
    LIMIT 1
```

## ClickHouse

TODO
