CREATE TABLE ethereum.traces
(
    `transaction_hash` String,
    `transaction_index` UInt16,
    `from_address` String,
    `to_address` String,
    `value` Decimal(38, 0),
    `input` String,
    `output` String,
    `trace_type` Enum8('call' = 1, 'create' = 2, 'suicide' = 3, 'reward' = 4, 'genesis' = 5, 'daofork' = 6),
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
)
ENGINE = MergeTree
ORDER BY (trace_type, block_number, block_timestamp)
