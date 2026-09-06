-- Use a dedicated demo service. Re-running this file leaves an existing
-- fixture intact; it does not append another 200M rows. Stop workloads before
-- reloading. After an interrupted INSERT, truncate sla_demo.events and reload.
CREATE DATABASE IF NOT EXISTS sla_demo;

CREATE TABLE IF NOT EXISTS sla_demo.events
(
    event_time  DateTime,
    user_id     UInt32,
    event_type  LowCardinality(String),
    country     LowCardinality(String),
    value       Float64
)
ENGINE = MergeTree
ORDER BY (event_type, event_time);

INSERT INTO sla_demo.events
SELECT
    now() - toIntervalSecond(number % 2592000),
    rand() % 1000000,
    ['click','view','purchase','signup','scroll'][1 + number % 5],
    ['US','GB','DE','FR','IN','BR'][1 + number % 6],
    rand() / 1e6
FROM numbers({rows:UInt64})
WHERE NOT EXISTS (SELECT 1 FROM sla_demo.events LIMIT 1);
