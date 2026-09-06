SELECT event_type, count(), avg(value), quantile(0.9)(value)
FROM sla_demo.events
WHERE event_type = 'purchase' AND event_time > now() - INTERVAL 1 DAY
GROUP BY event_type
SETTINGS log_comment = 'frontend-dashboard', log_queries = 1,
         log_queries_probability = 1, log_queries_min_query_duration_ms = 0,
         use_query_cache = 0
