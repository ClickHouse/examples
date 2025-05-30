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