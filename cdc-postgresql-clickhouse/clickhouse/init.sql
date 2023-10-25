CREATE TABLE IF NOT EXISTS demo_data (
    `before.id` Nullable(UInt32),
    `before.message` Nullable(String),
    `after.id` Nullable(UInt32),
    `after.message` Nullable(String),
    `source.table` Nullable(String),
    op LowCardinality(String)
) ENGINE = MergeTree()
ORDER BY tuple();
CREATE MATERIALIZED VIEW demo_table1_mv
(
    id UInt32,
    message String
) ENGINE = ReplacingMergeTree()
ORDER BY id
AS
SELECT
    `after.id` as id,
    `after.message` as message
FROM demo_data
WHERE `source.table` = 'demo_table1';
CREATE MATERIALIZED VIEW demo_table2_mv
(
    id UInt32,
    message String
) ENGINE = ReplacingMergeTree()
ORDER BY id
AS
SELECT
    `after.id` as id,
    `after.message` as message
FROM demo_data
WHERE `source.table` = 'demo_table2';
