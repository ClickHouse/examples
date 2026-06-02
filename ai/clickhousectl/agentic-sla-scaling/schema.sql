-- ~200M row events table.
-- the frontend query filters on event_type (uses the index -> fast),
-- the load query groups across all user_id (full scan -> heavy).

CREATE TABLE IF NOT EXISTS events
(
    event_time  DateTime,
    user_id     UInt32,
    event_type  LowCardinality(String),
    country     LowCardinality(String),
    value       Float64
)
ENGINE = MergeTree
ORDER BY (event_type, event_time);

INSERT INTO events
SELECT
    now() - toIntervalSecond(number % 2592000),
    rand() % 1000000,
    ['click','view','purchase','signup','scroll'][1 + number % 5],
    ['US','GB','DE','FR','IN','BR'][1 + (number % 6)],
    rand() / 1e6
FROM numbers(200000000);
