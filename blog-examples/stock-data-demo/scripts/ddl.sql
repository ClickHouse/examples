CREATE TABLE IF NOT EXISTS quotes
(
    `sym` LowCardinality(String),
    `bx` UInt8,
    `bp` Float64,
    `bs` UInt64,
    `ax` UInt8,
    `ap` Float64,
    `as` UInt64,
    `c` UInt8,
    `i` Array(UInt32),
    `t` UInt64,
    `q` UInt64,
    `z` Enum8('NYSE' = 1, 'AMEX' = 2, 'Nasdaq' = 3),
    `inserted_at` UInt64 DEFAULT toUnixTimestamp64Milli(now64())
)
ENGINE = MergeTree
ORDER BY (sym, t - (t % 60000));

CREATE TABLE IF NOT EXISTS trades
(
    `sym` LowCardinality(String),
    `i` String,
    `x` UInt8,
    `p` Float64,
    `s` UInt64,
    `ds` String DEFAULT '',
    `pt` UInt64 DEFAULT 0,
    `c` Array(UInt32),
    `t` UInt64,
    `q` UInt64,
    `z` Enum8('NYSE' = 1, 'AMEX' = 2, 'Nasdaq' = 3),
    `trfi` UInt64,
    `trft` UInt64,
    `inserted_at` UInt64 DEFAULT toUnixTimestamp64Milli(now64())
)
ENGINE = MergeTree
ORDER BY (sym, t - (t % 60000));
