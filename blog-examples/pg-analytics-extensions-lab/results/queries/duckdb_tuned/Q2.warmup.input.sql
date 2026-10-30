SET duckdb.force_execution = true; SET duckdb.max_memory = 2048; SET duckdb.max_workers_per_postgres_scan = 4; SET duckdb.threads_for_postgres_scan = 4; SET search_path = public;
\timing on
\echo WARMUP
SELECT event_type, count(*) AS n, sum(revenue) AS rev FROM events GROUP BY event_type ORDER BY event_type;
