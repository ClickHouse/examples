CREATE TABLE IF NOT EXISTS report_history.report_results
(
    tenant_id String,
    run_id FixedString(64),
    completed_at DateTime64(3, 'UTC'),
    row_number UInt32,
    region LowCardinality(String),
    category LowCardinality(String),
    revenue_cents Int64,
    units UInt32
)
ENGINE = ReplacingMergeTree
PARTITION BY toYYYYMM(completed_at)
ORDER BY (tenant_id, run_id, row_number)
