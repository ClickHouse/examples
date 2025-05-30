# Blocks

## Materialized Views

```sql
CREATE MATERIALIZED VIEW blocks_mv TO blocks
(
    `number` UInt32,
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
    `size` UInt32,
    `extra_data` String,
    `gas_limit` UInt32,
    `gas_used` UInt32,
    `timestamp` DateTime,
    `transaction_count` UInt16,
    `base_fee_per_gas` UInt64,
    `withdrawals_root` String,
    `withdrawals.index` Array(UInt64),
    `withdrawals.validator_index` Array(Int64),
    `withdrawals.address` Array(String),
    `withdrawals.amount` Array(UInt64)
) AS
SELECT
    JSONExtract(MessageData, 'number', 'UInt32') AS number,
    JSONExtractString(MessageData, 'hash') AS hash,
    JSONExtractString(MessageData, 'parent_hash') AS parent_hash,
    JSONExtractString(MessageData, 'nonce') AS nonce,
    JSONExtractString(MessageData, 'sha3_uncles') AS sha3_uncles,
    JSONExtractString(MessageData, 'logs_bloom') AS logs_bloom,
    JSONExtractString(MessageData, 'transactions_root') AS transactions_root,
    JSONExtractString(MessageData, 'state_root') AS state_root,
    JSONExtractString(MessageData, 'receipts_root') AS receipts_root,
    JSONExtractString(MessageData, 'miner') AS miner,
    JSONExtract(MessageData, 'difficulty', 'Decimal(38, 0)') AS difficulty,
    JSONExtract(MessageData, 'total_difficulty', 'Decimal(38, 0)') AS total_difficulty,
    JSONExtract(MessageData, 'size', 'UInt32') AS size,
    JSONExtractString(MessageData, 'extra_data') AS extra_data,
    JSONExtract(MessageData, 'gas_limit', 'UInt32') AS gas_limit,
    JSONExtract(MessageData, 'gas_used', 'UInt32') AS gas_used,
    JSONExtract(MessageData, 'timestamp', 'UInt64') AS timestamp,
    JSONExtract(MessageData, 'transaction_count', 'UInt16') AS transaction_count,
    JSONExtract(MessageData, 'base_fee_per_gas', 'UInt64') AS base_fee_per_gas,
    JSONExtract(MessageData, 'withdrawals_root', 'String') AS withdrawals_root,
    JSONExtract(MessageData, 'withdrawals', 'Nested(index UInt64, validator_index Int64, address String, amount UInt64)') AS withdrawals
FROM block_messages
SETTINGS allow_simdjson = 0
```

```sql
 CREATE TABLE block_messages
(
    `MessageData` String,
    `AttributesMap` Tuple(item_id String, item_timestamp String)
)
ENGINE = Null
```

