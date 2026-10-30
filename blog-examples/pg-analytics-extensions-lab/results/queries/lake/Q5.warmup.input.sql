SET search_path = ice, public;
\timing on
\echo WARMUP
SELECT count(DISTINCT user_id) FROM events;
