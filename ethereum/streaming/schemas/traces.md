# Traces

## Materialized Views

```sql
 CREATE MATERIALIZED VIEW traces_mv TO traces
(
    `transaction_hash` String,
    `transaction_index` UInt16,
    `from_address` String,
    `to_address` String,
    `value` Decimal(38, 0),
    `input` String,
    `output` String,
    `trace_type` Enum8('' = 0, 'call' = 1, 'create' = 2, 'suicide' = 3, 'reward' = 4, 'genesis' = 5, 'daofork' = 6),
    `call_type` Enum8('' = 0, 'call' = 1, 'callcode' = 2, 'delegatecall' = 3, 'staticcall' = 4),
    `reward_type` Enum8('' = 0, 'block' = 1, 'uncle' = 2),
    `gas` UInt32 CODEC(Delta(4), ZSTD(1)),
    `gas_used` UInt32,
    `subtraces` UInt32,
    `trace_address` String,
    `error` String,
    `status` Bool,
    `block_timestamp` DateTime CODEC(Delta(4), ZSTD(1)),
    `block_number` UInt32 CODEC(Delta(4), ZSTD(1)),
    `block_hash` String,
    `trace_id` String
) AS
SELECT
    JSONExtractString(MessageData, 'transaction_hash') AS transaction_hash,
    JSONExtractUInt(MessageData, 'transaction_index') AS transaction_index,
    JSONExtractString(MessageData, 'from_address') AS from_address,
    JSONExtractString(MessageData, 'to_address') AS to_address,
    JSONExtract(MessageData, 'value', 'Decimal(38, 0)') AS value,
    JSONExtractString(MessageData, 'input') AS input,
    JSONExtractString(MessageData, 'output') AS output,
    JSONExtractString(MessageData, 'trace_type') AS trace_type,
    JSONExtractString(MessageData, 'call_type') AS call_type,
    JSONExtractString(MessageData, 'reward_type') AS reward_type,
    JSONExtractUInt(MessageData, 'gas') AS gas,
    JSONExtractUInt(MessageData, 'gas_used') AS gas_used,
    JSONExtractUInt(MessageData, 'subtraces') AS subtraces,
    JSONExtractString(MessageData, 'trace_address') AS trace_address,
    JSONExtractString(MessageData, 'error') AS error,
    JSONExtractBool(MessageData, 'status') AS status,
    JSONExtractUInt(MessageData, 'block_timestamp') AS block_timestamp,
    JSONExtractUInt(MessageData, 'block_number') AS block_number,
    JSONExtractString(MessageData, 'block_hash') AS block_hash,
    JSONExtractString(MessageData, 'trace_id') AS trace_id
FROM trace_messages
SETTINGS allow_simdjson = 0
```

```sql
CREATE TABLE trace_messages
(
    `MessageData` String,
    `AttributesMap` Tuple(item_id String, item_timestamp String)
)
ENGINE = Null
```

