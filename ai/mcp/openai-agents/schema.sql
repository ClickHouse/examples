CREATE TABLE IF NOT EXISTS agent_spans_raw
(
    trace_id String,
    span_id String,
    parent_id String,
    started_at DateTime64(6, 'UTC'),
    ended_at DateTime64(6, 'UTC'),
    span_type LowCardinality(String),
    span_name String,
    model String,
    error String,
    span_data String
)
ENGINE = MergeTree
ORDER BY (started_at, trace_id, span_id);

-- Column names match a ClickStack trace source. Duration is in nanoseconds.
CREATE VIEW IF NOT EXISTS agent_spans AS
SELECT
    started_at AS Timestamp,
    trace_id AS TraceId,
    span_id AS SpanId,
    parent_id AS ParentSpanId,
    span_name AS SpanName,
    'Internal' AS SpanKind,
    'openai-agents-example' AS ServiceName,
    map('model', model, 'span_type', span_type, 'span_data', span_data) AS SpanAttributes,
    map('service.name', 'openai-agents-example') AS ResourceAttributes,
    toUInt64(greatest(dateDiff('microsecond', started_at, ended_at), 0)) * 1000 AS Duration,
    if(empty(error), 'Ok', 'Error') AS StatusCode,
    error AS StatusMessage
FROM agent_spans_raw;
