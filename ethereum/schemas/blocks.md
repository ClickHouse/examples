## Blocks

## BigQuery Schema

```sql
CREATE TABLE `clickhouse-cloud.crypto_ethereum.blocks`
(
 timestamp TIMESTAMP NOT NULL OPTIONS(description="The timestamp for when the block was collated"),
 number INT64 NOT NULL OPTIONS(description="The block number"),
 `hash` STRING NOT NULL OPTIONS(description="Hash of the block"),
 parent_hash STRING OPTIONS(description="Hash of the parent block"),
 nonce STRING NOT NULL OPTIONS(description="Hash of the generated proof-of-work"),
 sha3_uncles STRING OPTIONS(description="SHA3 of the uncles data in the block"),
 logs_bloom STRING OPTIONS(description="The bloom filter for the logs of the block"),
 transactions_root STRING OPTIONS(description="The root of the transaction trie of the block"),
 state_root STRING OPTIONS(description="The root of the final state trie of the block"),
 receipts_root STRING OPTIONS(description="The root of the receipts trie of the block"),
 miner STRING OPTIONS(description="The address of the beneficiary to whom the mining rewards were given"),
 difficulty NUMERIC OPTIONS(description="Integer of the difficulty for this block"),
 total_difficulty NUMERIC OPTIONS(description="Integer of the total difficulty of the chain until this block"),
 size INT64 OPTIONS(description="The size of this block in bytes"),
 extra_data STRING OPTIONS(description="The extra data field of this block"),
 gas_limit INT64 OPTIONS(description="The maximum gas allowed in this block"),
 gas_used INT64 OPTIONS(description="The total used gas by all transactions in this block"),
 transaction_count INT64 OPTIONS(description="The number of transactions in the block"),
 base_fee_per_gas INT64 OPTIONS(description="Protocol base fee per gas, which can move up or down")
)
PARTITION BY DATE(timestamp)
OPTIONS(
 description="The Ethereum blockchain is composed of a series of blocks. This table contains a set of all blocks in the blockchain and their attributes.\nData is exported using https://github.com/medvedev1088/ethereum-etl"
);
```

## ClickHouse Schema

```sql
CREATE TABLE ethereum.blocks
(
    `number` UInt32 CODEC(Delta(4), ZSTD(1)),
    `hash` String,
    `parent_hash` String,
    `nonce` String,
    `sha3_uncles` String,
    `logs_bloom` String,
    `transactions_root` String,
    `state_root` String,
    `receipts_root` String,
    `miner` String,
    `difficulty` Decimal(38, 0),
    `total_difficulty` Decimal(38, 0),
    `size` UInt32 CODEC(Delta(4), ZSTD(1)),
    `extra_data` String,
    `gas_limit` UInt32 CODEC(Delta(4), ZSTD(1)),
    `gas_used` UInt32 CODEC(Delta(4), ZSTD(1)),
    `timestamp` DateTime CODEC(Delta(4), ZSTD(1)),
    `transaction_count` UInt16,
    `base_fee_per_gas` UInt64
)
ENGINE = MergeTree
ORDER BY timestamp
```

## Load instructions (public bucket - CSV files)

```sql
INSERT INTO blocks SELECT
    number,
    hash,
    parent_hash,
    nonce,
    sha3_uncles,
    logs_bloom,
    transactions_root,
    state_root,
    receipts_root,
    miner,
    difficulty,
    total_difficulty,
    size,
    extra_data,
    gas_limit,
    gas_used,
    timestamp,
    transaction_count,
    base_fee_per_gas
FROM s3('https://storage.googleapis.com/clickhouse_public_datasets/ethereum/blocks/*.gz', 'CSVWithNames', 'timestamp DateTime, number Int64, hash String, parent_hash String, nonce String, sha3_uncles String, logs_bloom String, transactions_root String, state_root String, receipts_root String, miner String, difficulty Decimal(38, 0), total_difficulty Decimal(38, 0), size Int64, extra_data String, gas_limit Int64,gas_used Int64,transaction_count Int64,base_fee_per_gas Int64')
```