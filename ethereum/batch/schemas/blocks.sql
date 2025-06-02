CREATE TABLE ethereum.blocks
(
	`number` UInt32 CODEC(Delta(4), ZSTD(1)) DEFAULT 0,
	`hash` String DEFAULT '',
	`parent_hash` String DEFAULT '',
	`nonce` String DEFAULT '',
	`sha3_uncles` String DEFAULT '',
	`logs_bloom` String DEFAULT '',
	`transactions_root` String DEFAULT '',
	`state_root` String DEFAULT '',
	`receipts_root` String DEFAULT '',
	`miner` String DEFAULT '',
	`difficulty` Decimal(38, 0) DEFAULT 0,
	`total_difficulty` Decimal(38, 0) DEFAULT 0,
	`size` UInt32 CODEC(Delta(4), ZSTD(1)) DEFAULT 0,
	`extra_data` String DEFAULT '',
	`gas_limit` UInt32 CODEC(Delta(4), ZSTD(1)) DEFAULT 0,
	`gas_used` UInt32 CODEC(Delta(4), ZSTD(1)) DEFAULT 0,
	`timestamp` DateTime CODEC(Delta(4), ZSTD(1)) DEFAULT '1970-01-01 00:00:00',
	`transaction_count` UInt16 DEFAULT 0,
	`base_fee_per_gas` UInt64 DEFAULT 0,
)
ENGINE = MergeTree
ORDER BY timestamp