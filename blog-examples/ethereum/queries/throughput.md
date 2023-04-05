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

```
SELECT
    'ethereum' AS chain,
     count() / (24 * 60 * 60 / count() OVER (PARTITION BY DATE(block_timestamp))) AS throughput,
     block_timestamp AS time
FROM ethereum.transactions
GROUP BY block_timestamp, block_number
ORDER BY block_timestamp ASC
LIMIT 100
```

avg per day
```
WITH
    THROUGHPUT_PER_TIME AS (
        SELECT
            'ethereum' AS chain,
            count() / (24 * 60 * 60 / count() OVER (PARTITION BY DATE(block_timestamp))) AS throughput,
            block_timestamp AS time
        FROM ethereum.transactions
        GROUP BY block_timestamp, block_number
        ORDER BY block_timestamp ASC
    )
SELECT
    'ethereum' AS chain,
    avg(throughput) as avg_throughput,
    toDate(time) as day
FROM THROUGHPUT_PER_TIME
GROUP BY day
ORDER BY day asc
LIMIT 100
```

avg per day - simplified
```
SELECT
     count() / (24 * 60 * 60 / count() OVER (PARTITION BY day)) AS throughput,
     toDate(block_timestamp) AS day
FROM ethereum.transactions
GROUP BY day
ORDER BY day ASC
LIMIT 1000

SELECT
     count()  AS throughput,
     toDate(block_timestamp) AS day
FROM ethereum.transactions
GROUP BY day
ORDER BY day ASC
LIMIT 5000
```