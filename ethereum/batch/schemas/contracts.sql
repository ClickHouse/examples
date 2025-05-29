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