SET search_path = ch, public;
\timing on
\echo WARMUP
SELECT count(*), sum(revenue) FROM events;
