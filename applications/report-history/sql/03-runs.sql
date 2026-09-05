CREATE TABLE IF NOT EXISTS report_history.report_runs
(
    tenant_id String,
    run_id FixedString(64),
    completed_at DateTime64(3, 'UTC'),
    report_type LowCardinality(String),
    source_uri String,
    artifact_uri String,
    expected_rows UInt32,
    summary_json String
)
ENGINE = ReplacingMergeTree
ORDER BY (tenant_id, run_id)
