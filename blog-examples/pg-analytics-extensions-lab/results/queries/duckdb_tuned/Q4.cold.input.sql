SET duckdb.force_execution = true; SET duckdb.max_memory = 2048; SET duckdb.max_workers_per_postgres_scan = 4; SET duckdb.threads_for_postgres_scan = 4; SET search_path = public;
\timing on
\echo RUN 1
SELECT user_id, sum(revenue) AS rev, count(*) AS n FROM events GROUP BY user_id ORDER BY rev DESC, user_id LIMIT 10;
