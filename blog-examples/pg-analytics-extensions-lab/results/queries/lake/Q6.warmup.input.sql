SET search_path = ice, public;
\timing on
\echo WARMUP
SELECT u.plan, count(*) AS n, sum(e.revenue) AS rev FROM events e JOIN users u ON u.user_id = e.user_id WHERE e.event_time >= '2026-03-01 00:00:00+00' AND e.event_time < '2026-04-01 00:00:00+00' GROUP BY u.plan ORDER BY u.plan;
