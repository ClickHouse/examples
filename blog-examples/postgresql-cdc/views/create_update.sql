CREATE MATERIALIZED VIEW default.uk_price_paid_mv TO default.uk_price_paid
(
    `id` Nullable(UInt64),
    `price` Nullable(UInt32),
    `date` Nullable(Date),
    `postcode1` Nullable(String),
    `postcode2` Nullable(String),
    `type` Nullable(Enum8('other' = 0, 'terraced' = 1, 'semi-detached' = 2, 'detached' = 3, 'flat' = 4)),
    `is_new` Nullable(UInt8),
    `duration` Nullable(Enum8('unknown' = 0, 'freehold' = 1, 'leasehold' = 2)),
    `addr1` Nullable(String),
    `addr2` Nullable(String),
    `street` Nullable(String),
    `locality` Nullable(String),
    `town` Nullable(String),
    `district` Nullable(String),
    `county` Nullable(String),
    `version` UInt64,
    `deleted` UInt8
) AS
SELECT
    after.id AS id,
    after.price AS price,
    toDate(after.date) AS date,
    after.postcode1 AS postcode1,
    after.postcode2 AS postcode2,
    after.type AS type,
    after.is_new AS is_new,
    after.duration AS duration,
    after.addr1 AS addr1,
    after.addr2 AS addr2,
    after.street AS street,
    after.locality AS locality,
    after.town AS town,
    after.district AS district,
    after.county AS county,
    source.lsn AS version
FROM uk_price_paid_changes
WHERE (op = 'c') OR (op = 'r') OR (op = 'u')
