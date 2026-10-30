SET duckdb.force_execution = true; SET search_path = public;
\timing on
\echo RUN 1
SELECT count(*), sum(revenue) FROM events;
