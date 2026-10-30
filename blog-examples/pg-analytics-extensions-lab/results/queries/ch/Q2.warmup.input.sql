SET search_path = ch, public;
\timing on
\echo WARMUP
SELECT event_type, count(*) AS n, sum(revenue) AS rev FROM events GROUP BY event_type ORDER BY event_type;
