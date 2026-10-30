SET duckdb.force_execution = true; SET search_path = public;
\timing on
\echo WARMUP
SELECT user_id, sum(revenue) AS rev, count(*) AS n FROM events GROUP BY user_id ORDER BY rev DESC, user_id LIMIT 10;
