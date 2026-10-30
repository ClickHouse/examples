SET duckdb.force_execution = true; SET search_path = public;
\timing on
\echo RUN 1
SELECT event_type, count(*) AS n, sum(revenue) AS rev FROM events GROUP BY event_type ORDER BY event_type;
