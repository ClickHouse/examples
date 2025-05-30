# Transactions

## Materialized Views

```sql
CREATE MATERIALIZED VIEW transactions_mv TO transactions
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
    `transaction_type` UInt8,
    `receipt_cumulative_gas_used` UInt32,
    `receipt_gas_used` UInt32,
    `receipt_contract_address` String,
    `receipt_root` String,
    `receipt_status` UInt8,
    `receipt_effective_gas_price` UInt64
) AS
SELECT
    JSONExtractString(MessageData, 'hash') AS hash,
    JSONExtract(MessageData, 'nonce', 'UInt32') AS nonce,
    JSONExtractString(MessageData, 'block_hash') AS block_hash,
    JSONExtract(MessageData, 'block_number', 'UInt32') AS block_number,
    JSONExtract(MessageData, 'transaction_index', 'UInt16') AS transaction_index,
    JSONExtractString(MessageData, 'from_address') AS from_address,
    JSONExtractString(MessageData, 'to_address') AS to_address,
    JSONExtract(MessageData, 'value', 'Decimal(38, 0)') AS value,
    JSONExtract(MessageData, 'gas', 'UInt32') AS gas,
    JSONExtract(MessageData, 'gas_price', 'UInt64') AS gas_price,
    JSONExtractString(MessageData, 'input') AS input,
    JSONExtract(MessageData, 'block_timestamp', 'UInt64') AS block_timestamp,
    JSONExtract(MessageData, 'max_fee_per_gas', 'UInt64') AS max_fee_per_gas,
    JSONExtract(MessageData, 'max_priority_fee_per_gas', 'UInt64') AS max_priority_fee_per_gas,
    JSONExtract(MessageData, 'transaction_type', 'UInt8') AS transaction_type,
    JSONExtract(MessageData, 'receipt_cumulative_gas_used', 'UInt32') AS receipt_cumulative_gas_used,
    JSONExtract(MessageData, 'receipt_gas_used', 'UInt32') AS receipt_gas_used,
    JSONExtractString(MessageData, 'receipt_contract_address') AS receipt_contract_address,
    JSONExtractString(MessageData, 'receipt_root') AS receipt_root,
    JSONExtract(MessageData, 'receipt_status', 'UInt8') AS receipt_status,
    JSONExtract(MessageData, 'receipt_effective_gas_price', 'UInt64') AS receipt_effective_gas_price
FROM transaction_messages
SETTINGS allow_simdjson = 0
```

```sql
CREATE TABLE transaction_messages
(
    `MessageData` String,
    `AttributesMap` Tuple(item_id String, item_timestamp String)
)
ENGINE = Null
```

