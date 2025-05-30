-- Originally from https://github.com/blockchain-etl/awesome-bigquery-views#transaction-throughput-comparison and https://evgemedvedev.medium.com/comparing-transaction-throughputs-for-8-blockchains-in-google-bigquery-with-google-data-studio-edbabb75b7f1

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

/* -- Alternative approaches to the query

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
*/