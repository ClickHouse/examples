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
    if(op = 'd', before.id, after.id) AS id,
    if(op = 'd', before.price, after.price) AS price,
    if(op = 'd', toDate(before.date), toDate(after.date)) AS date,
    if(op = 'd', before.postcode1, after.postcode1) AS postcode1,
    if(op = 'd', before.postcode2, after.postcode2) AS postcode2,
    if(op = 'd', before.type, after.type) AS type,
    if(op = 'd', before.is_new, after.is_new) AS is_new,
    if(op = 'd', before.duration, after.duration) AS duration,
    if(op = 'd', before.addr1, after.addr1) AS addr1,
    if(op = 'd', before.addr2, after.addr2) AS addr2,
    if(op = 'd', before.street, after.street) AS street,
    if(op = 'd', before.locality, after.locality) AS locality,
    if(op = 'd', before.town, after.town) AS town,
    if(op = 'd', before.district, after.district) AS district,
    if(op = 'd', before.county, after.county) AS county,
    if(op = 'd', source.lsn, source.lsn) AS version,
    if(op = 'd', 1, 0) AS deleted
FROM default.uk_price_paid_changes
WHERE (op = 'c') OR (op = 'r') OR (op = 'u') OR (op = 'd')
