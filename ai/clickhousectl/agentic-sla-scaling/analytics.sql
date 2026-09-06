SELECT user_id, count(), avg(sin(value) + cos(value))
FROM sla_demo.events
GROUP BY user_id
ORDER BY count() DESC
LIMIT 20
SETTINGS log_comment = 'analytics-batch', log_queries = 1,
         log_queries_probability = 1, log_queries_min_query_duration_ms = 0,
         use_query_cache = 0
