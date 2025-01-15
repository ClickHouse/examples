CREATE TABLE bluesky
(
    `data` JSON(
        kind LowCardinality(String),
        commit.operation LowCardinality(String),
        commit.collection LowCardinality(String),
        time_us UInt64)
)
ORDER BY (
    data.kind,
    data.commit.operation,
    data.commit.collection,
    fromUnixTimestamp64Micro(data.time_us));
