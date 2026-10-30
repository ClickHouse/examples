SET search_path = ch, public;
\timing on
\echo WARMUP
SELECT count(DISTINCT user_id) FROM events;
