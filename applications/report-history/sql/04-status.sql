CREATE TABLE IF NOT EXISTS report_history.run_status
(
    tenant_id String,
    run_id String,
    version UInt64,
    status Enum8('queued' = 1, 'running' = 2, 'completed' = 3, 'failed' = 4),
    observed_at DateTime64(3, 'UTC'),
    detail String
)
ENGINE = ReplacingMergeTree(version)
ORDER BY (tenant_id, run_id)
