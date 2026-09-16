CREATE TABLE IF NOT EXISTS click_events (
  event_id UUID,
  account_id UUID,
  link_id UUID,
  occurred_at DateTime64(3, 'UTC'),
  ingested_at DateTime64(3, 'UTC') DEFAULT now64(3),
  utm_source String,
  utm_medium String,
  utm_campaign String,
  utm_term String,
  utm_content String,
  referrer_domain String,
  country LowCardinality(String),
  device LowCardinality(String),
  browser LowCardinality(String),
  is_bot UInt8,
  is_demo UInt8 DEFAULT 0
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(occurred_at)
ORDER BY (account_id, occurred_at, link_id, event_id)
TTL occurred_at + INTERVAL 180 DAY DELETE;

-- Retry-safe counts use uniqExact(event_id). A sorting key does not deduplicate.
-- ClickPipes creates cdc_links separately. Do not create its cloud table here.
