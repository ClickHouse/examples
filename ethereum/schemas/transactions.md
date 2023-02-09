# Transactions

## BigQuery Schema

```sql
CREATE TABLE `clickhouse-cloud.crypto_ethereum.transactions`
(
  `hash` STRING NOT NULL OPTIONS(description="Hash of the transaction"),
  nonce INT64 NOT NULL OPTIONS(description="The number of transactions made by the sender prior to this one"),
  transaction_index INT64 NOT NULL OPTIONS(description="Integer of the transactions index position in the block"),
  from_address STRING NOT NULL OPTIONS(description="Address of the sender"),
  to_address STRING OPTIONS(description="Address of the receiver. null when its a contract creation transaction"),
  value NUMERIC OPTIONS(description="Value transferred in Wei"),
  gas INT64 OPTIONS(description="Gas provided by the sender"),
  gas_price INT64 OPTIONS(description="Gas price provided by the sender in Wei"),
  input STRING OPTIONS(description="The data sent along with the transaction"),
  receipt_cumulative_gas_used INT64 OPTIONS(description="The total amount of gas used when this transaction was executed in the block"),
  receipt_gas_used INT64 OPTIONS(description="The amount of gas used by this specific transaction alone"),
  receipt_contract_address STRING OPTIONS(description="The contract address created, if the transaction was a contract creation, otherwise null"),
  receipt_root STRING OPTIONS(description="32 bytes of post-transaction stateroot (pre Byzantium)"),
  receipt_status INT64 OPTIONS(description="Either 1 (success) or 0 (failure) (post Byzantium)"),
  block_timestamp TIMESTAMP NOT NULL OPTIONS(description="Timestamp of the block where this transaction was in"),
  block_number INT64 NOT NULL OPTIONS(description="Block number where this transaction was in"),
  block_hash STRING NOT NULL OPTIONS(description="Hash of the block where this transaction was in"),
  max_fee_per_gas INT64 OPTIONS(description="Total fee that covers both base and priority fees"),
  max_priority_fee_per_gas INT64 OPTIONS(description="Fee given to miners to incentivize them to include the transaction"),
  transaction_type INT64 OPTIONS(description="Transaction type"),
  receipt_effective_gas_price INT64 OPTIONS(description="The actual value per gas deducted from the senders account. Replacement of gas_price after EIP-1559")
)
PARTITION BY DATE(block_timestamp)
OPTIONS(
  description="Each block in the blockchain is composed of zero or more transactions. Each transaction has a source address, a target address, an amount of Ether transferred, and an array of input bytes.\nThis table contains a set of all transactions from all blocks, and contains a block identifier to get associated block-specific information associated with each transaction.\nData is exported using https://github.com/medvedev1088/ethereum-etl\n"
);
```

## ClickHouse Schema

```sql
CREATE TABLE ethereum.transactions
(
    `hash` String,
    `nonce` UInt32,
    `block_hash` String,
    `block_number` UInt32 CODEC(Delta(4), ZSTD(1)),
    `transaction_index` UInt16,
    `from_address` String,
    `to_address` String,
    `value` Decimal(38, 0),
    `gas` UInt32 CODEC(Delta(4), ZSTD(1)),
    `gas_price` UInt64,
    `input` String,
    `block_timestamp` DateTime CODEC(Delta(4), ZSTD(1)),
    `max_fee_per_gas` UInt64,
    `max_priority_fee_per_gas` UInt64,
    `transaction_type` Nullable(UInt8),
    `receipt_cumulative_gas_used` UInt32,
    `receipt_gas_used` UInt32,
    `receipt_contract_address` String,
    `receipt_root` String,
    `receipt_status` Nullable(UInt8),
    `receipt_effective_gas_price` UInt64
)
ENGINE = MergeTree
ORDER BY (block_timestamp, block_number)
```

## Load instructions (public bucket - CSV files)

```sql
INSERT INTO t SELECT
    hash,
    nonce,
    block_hash,
    block_number,
    transaction_index,
    from_address,
    to_address,
    value,
    gas,
    gas_price,
    input,
    toInt64(block_timestamp) AS block_timestamp,
    max_fee_per_gas,
    max_priority_fee_per_gas,
    transaction_type,
    receipt_cumulative_gas_used,
    receipt_gas_used,
    receipt_contract_address,
    receipt_root,
    receipt_status,
    receipt_effective_gas_price
FROM s3('https://storage.googleapis.com/clickhouse_public_datasets/ethereum/transactions/*.csv.gz', 'CSVWithNames', 'hash String, nonce Int64, transaction_index Int64,from_address String, to_address Nullable(String), value Decimal(38, 0), gas Int64, gas_price Int64, input String, receipt_cumulative_gas_used Int64,receipt_gas_used Int64,receipt_contract_address Nullable(String),receipt_root String,receipt_status Nullable(Int64),block_timestamp DateTime, block_number Int64, block_hash String, max_fee_per_gas Nullable(Int64), max_priority_fee_per_gas Nullable(Int64), transaction_type Int64, receipt_effective_gas_price Int64')
```