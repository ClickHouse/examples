-- Originally from https://github.com/blockchain-etl/awesome-bigquery-views#transaction-throughput-comparison and https://evgemedvedev.medium.com/comparing-transaction-throughputs-for-8-blockchains-in-google-bigquery-with-google-data-studio-edbabb75b7f1

SELECT
    'ethereum' AS chain,
     count() / (24 * 60 * 60 / count() OVER (PARTITION BY DATE(block_timestamp))) AS throughput,
     block_timestamp AS time
FROM ethereum.transactions
GROUP BY block_timestamp, block_number
ORDER BY block_timestamp ASC
LIMIT 100