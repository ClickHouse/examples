SET duckdb.force_execution = true; SET search_path = public;
\timing on
\echo RUN 1
SELECT count(DISTINCT user_id) FROM events;
\echo RUN 2
SELECT count(DISTINCT user_id) FROM events;
\echo RUN 3
SELECT count(DISTINCT user_id) FROM events;
\echo RUN 4
SELECT count(DISTINCT user_id) FROM events;
