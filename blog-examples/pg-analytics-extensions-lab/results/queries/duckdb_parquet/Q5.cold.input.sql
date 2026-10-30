SET duckdb.force_execution = true; SET duckdb.max_memory = 2048; SET search_path = duckpq, public;
\timing on
\echo RUN 1
SELECT count(DISTINCT user_id) FROM events;
