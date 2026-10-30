CREATE DATABASE IF NOT EXISTS lab;
DROP TABLE IF EXISTS lab.events;
DROP TABLE IF EXISTS lab.users;
CREATE TABLE lab.events (
  event_id    Int64,
  event_time  DateTime64(6, 'UTC'),
  user_id     Int64,
  event_type  LowCardinality(String),
  country     LowCardinality(String),
  url         String,
  duration_ms Int32,
  revenue     Decimal(10, 2)
) ENGINE = MergeTree ORDER BY event_time;
CREATE TABLE lab.users (
  user_id     Int64,
  signup_date Date,
  plan        LowCardinality(String),
  country     LowCardinality(String)
) ENGINE = MergeTree ORDER BY user_id;
