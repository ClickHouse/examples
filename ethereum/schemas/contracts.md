# Contracts

## BigQuery Schema

```sql
CREATE TABLE `bigquery-public-data.crypto_ethereum.contracts`
(
  address STRING NOT NULL OPTIONS(description="Address of the contract"),
  bytecode STRING OPTIONS(description="Bytecode of the contract"),
  function_sighashes ARRAY<STRING> OPTIONS(description="4-byte function signature hashes"),
  is_erc20 BOOL OPTIONS(description="Whether this contract is an ERC20 contract"),
  is_erc721 BOOL OPTIONS(description="Whether this contract is an ERC721 contract"),
  block_timestamp TIMESTAMP NOT NULL OPTIONS(description="Timestamp of the block where this contract was created"),
  block_number INT64 NOT NULL OPTIONS(description="Block number where this contract was created"),
  block_hash STRING NOT NULL OPTIONS(description="Hash of the block where this contract was created")
)
PARTITION BY DATE(block_timestamp)
OPTIONS(
  description="Some transactions create smart contracts from their input bytes, and this smart contract is stored at a particular 20-byte address.\nThis table contains a subset of Ethereum addresses that contain contract byte-code, as well as some basic analysis of that byte-code.\nData is exported using https://github.com/medvedev1088/ethereum-etl"
);
```

## ClickHouse Schema

```sql
CREATE TABLE ethereum.contracts
(
    `address` LowCardinality(String),
    `bytecode` LowCardinality(String) CODEC(ZSTD(9)),
    `function_sighashes` Array(String),
    `is_erc20` Bool,
    `is_erc721` Bool,
    `block_timestamp` DateTime CODEC(Delta(4), ZSTD(1)),
    `block_number` UInt32 CODEC(Delta(4), ZSTD(1)),
    `block_hash` LowCardinality(String) CODEC(ZSTD(9))
)
ENGINE = MergeTree
ORDER BY (is_erc721, block_number, address)
```

## Load instructions (public bucket - Parquet files)

```sql
INSERT INTO contracts
SELECT *
FROM s3('https://storage.googleapis.com/clickhouse_public_datasets/ethereum/contracts/*.parquet')
```
