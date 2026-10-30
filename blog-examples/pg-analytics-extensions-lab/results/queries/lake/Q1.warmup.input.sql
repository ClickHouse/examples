SET search_path = ice, public;
\timing on
\echo WARMUP
SELECT count(*), sum(revenue) FROM events;
