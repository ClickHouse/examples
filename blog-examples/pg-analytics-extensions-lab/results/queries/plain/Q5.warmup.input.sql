SET search_path = public;
\timing on
\echo WARMUP
SELECT count(DISTINCT user_id) FROM events;
