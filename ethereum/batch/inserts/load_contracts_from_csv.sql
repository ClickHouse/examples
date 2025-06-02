INSERT INTO contracts
SELECT *
FROM s3('https://storage.googleapis.com/clickhouse_public_datasets/ethereum/contracts/*.parquet')