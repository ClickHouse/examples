CREATE TABLE events
(
    event_id Int64,
    name String
)
ENGINE = MergeTree
ORDER BY event_id;

CREATE TABLE events_queue
(
    event_id Int64,
    name String
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'redpanda:9092',
    kafka_topic_list = 'events',
    kafka_group_name = 'clickhouse-events-demo',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 1,
    kafka_flush_interval_ms = 1000;

CREATE MATERIALIZED VIEW events_mv TO events
AS SELECT event_id, name FROM events_queue;
