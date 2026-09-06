-- Exact p99 of successful initial dashboard queries completed in the last
-- minute, across all replicas. Failed requests are counted separately.
-- An empty successful set returns 0 here; common.sh displays it as NO_DATA.
SELECT
    countIf(type = 'QueryFinish') AS completed,
    countIf(type IN ('ExceptionBeforeStart', 'ExceptionWhileProcessing')) AS failed,
    quantileExactIf(0.99)(query_duration_ms, type = 'QueryFinish') AS p99_ms
FROM clusterAllReplicas(default, system.query_log)
WHERE event_time > now() - INTERVAL 1 MINUTE
  AND is_initial_query = 1
  AND log_comment = 'frontend-dashboard'
  AND type IN ('QueryFinish', 'ExceptionBeforeStart', 'ExceptionWhileProcessing')
