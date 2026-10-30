SET duckdb.force_execution = true; SET search_path = public;
\timing on
\echo WARMUP
SELECT count(*), sum(revenue) FROM events;
