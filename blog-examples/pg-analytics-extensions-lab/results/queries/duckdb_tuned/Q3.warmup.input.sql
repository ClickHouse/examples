SET duckdb.force_execution = true; SET duckdb.max_memory = 2048; SET duckdb.max_workers_per_postgres_scan = 4; SET duckdb.threads_for_postgres_scan = 4; SET search_path = public;
\timing on
\echo WARMUP
SELECT country, date_trunc('day', event_time) AS day, count(*) AS n, sum(revenue) AS rev FROM events WHERE event_time >= '2026-02-01 00:00:00+00' AND event_time < '2026-03-01 00:00:00+00' AND event_type IN ('purchase', 'add_to_cart', 'checkout_start') GROUP BY country, day ORDER BY day, country;
