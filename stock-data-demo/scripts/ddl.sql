CREATE TABLE quotes
(
    `sym` LowCardinality(String),
    `bx` UInt8,
    `bp` Float64,
    `bs` UInt64,
    `ax` UInt8,
    `ap` Float64,
    `as` UInt64,
    `c` UInt8,
    `i` Array(UInt8),
    `t` UInt64,
    `q` UInt64,
    `z` Enum8('NYSE' = 1, 'AMEX' = 2, 'Nasdaq' = 3),
    `inserted_at` UInt64 DEFAULT toUnixTimestamp64Milli(now64())
)
ORDER BY (sym, t - (t % 60000))

CREATE TABLE trades
(
    `sym` LowCardinality(String),
    `i` String,
    `x` UInt8,
    `p` Float64,
    `s` UInt64,
    `c` Array(UInt8),
    `t` UInt64,
    `q` UInt64,
    `z` Enum8('NYSE' = 1, 'AMEX' = 2, 'Nasdaq' = 3),
    `trfi` UInt64,
    `trft` UInt64,
    `inserted_at` UInt64 DEFAULT toUnixTimestamp64Milli(now64())
)
ORDER BY (sym, t - (t % 60000))
