SET duckdb.force_execution = true; SET duckdb.max_memory = 2048; SET search_path = duckpq, public;
\timing on
\echo RUN 1
SELECT count(DISTINCT user_id) FROM events;
\echo RUN 2
SELECT count(DISTINCT user_id) FROM events;
\echo RUN 3
SELECT count(DISTINCT user_id) FROM events;
\echo RUN 4
SELECT count(DISTINCT user_id) FROM events;
\echo RUN 5
SELECT count(DISTINCT user_id) FROM events;
\echo RUN 6
SELECT count(DISTINCT user_id) FROM events;
\echo RUN 7
SELECT count(DISTINCT user_id) FROM events;
\echo RUN 8
SELECT count(DISTINCT user_id) FROM events;
\echo RUN 9
SELECT count(DISTINCT user_id) FROM events;
\echo RUN 10
SELECT count(DISTINCT user_id) FROM events;
