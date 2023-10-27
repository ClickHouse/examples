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
TO demo_table1_data
AS
SELECT
    `after.id` as id,
    `after.message` as message
FROM demo_data
WHERE `source.table` = 'demo_table1';
CREATE TABLE demo_table1_data
(
    id UInt32,
    message String
)
ENGINE = ReplacingMergeTree()
ORDER BY id;
CREATE MATERIALIZED VIEW demo_table2_mv
TO demo_table2_data
AS
SELECT
    `after.id` as id,
    `after.message` as message
FROM demo_data
WHERE `source.table` = 'demo_table2';
CREATE TABLE demo_table2_data
(
    id UInt32,
    message String
) ENGINE = ReplacingMergeTree()
ORDER BY id;
