CREATE TABLE bluesky
(
    `data` JSON(
        kind LowCardinality(String),
        commit.operation LowCardinality(String),
        commit.collection LowCardinality(String),
        did String,
        time_us UInt64)  CODEC(ZSTD(1))
)
ORDER BY (
    data.kind,
    data.commit.operation,
    data.commit.collection,
    data.did,
    fromUnixTimestamp64Micro(data.time_us));