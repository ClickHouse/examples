SET search_path = ch, public;
\timing on
\echo RUN 1
SELECT u.plan, count(*) AS n, sum(e.revenue) AS rev FROM events e JOIN users u ON u.user_id = e.user_id WHERE e.event_time >= '2026-03-01 00:00:00+00' AND e.event_time < '2026-04-01 00:00:00+00' GROUP BY u.plan ORDER BY u.plan;
\echo RUN 2
SELECT u.plan, count(*) AS n, sum(e.revenue) AS rev FROM events e JOIN users u ON u.user_id = e.user_id WHERE e.event_time >= '2026-03-01 00:00:00+00' AND e.event_time < '2026-04-01 00:00:00+00' GROUP BY u.plan ORDER BY u.plan;
\echo RUN 3
SELECT u.plan, count(*) AS n, sum(e.revenue) AS rev FROM events e JOIN users u ON u.user_id = e.user_id WHERE e.event_time >= '2026-03-01 00:00:00+00' AND e.event_time < '2026-04-01 00:00:00+00' GROUP BY u.plan ORDER BY u.plan;
\echo RUN 4
SELECT u.plan, count(*) AS n, sum(e.revenue) AS rev FROM events e JOIN users u ON u.user_id = e.user_id WHERE e.event_time >= '2026-03-01 00:00:00+00' AND e.event_time < '2026-04-01 00:00:00+00' GROUP BY u.plan ORDER BY u.plan;
\echo RUN 5
SELECT u.plan, count(*) AS n, sum(e.revenue) AS rev FROM events e JOIN users u ON u.user_id = e.user_id WHERE e.event_time >= '2026-03-01 00:00:00+00' AND e.event_time < '2026-04-01 00:00:00+00' GROUP BY u.plan ORDER BY u.plan;
\echo RUN 6
SELECT u.plan, count(*) AS n, sum(e.revenue) AS rev FROM events e JOIN users u ON u.user_id = e.user_id WHERE e.event_time >= '2026-03-01 00:00:00+00' AND e.event_time < '2026-04-01 00:00:00+00' GROUP BY u.plan ORDER BY u.plan;
\echo RUN 7
SELECT u.plan, count(*) AS n, sum(e.revenue) AS rev FROM events e JOIN users u ON u.user_id = e.user_id WHERE e.event_time >= '2026-03-01 00:00:00+00' AND e.event_time < '2026-04-01 00:00:00+00' GROUP BY u.plan ORDER BY u.plan;
\echo RUN 8
SELECT u.plan, count(*) AS n, sum(e.revenue) AS rev FROM events e JOIN users u ON u.user_id = e.user_id WHERE e.event_time >= '2026-03-01 00:00:00+00' AND e.event_time < '2026-04-01 00:00:00+00' GROUP BY u.plan ORDER BY u.plan;
\echo RUN 9
SELECT u.plan, count(*) AS n, sum(e.revenue) AS rev FROM events e JOIN users u ON u.user_id = e.user_id WHERE e.event_time >= '2026-03-01 00:00:00+00' AND e.event_time < '2026-04-01 00:00:00+00' GROUP BY u.plan ORDER BY u.plan;
\echo RUN 10
SELECT u.plan, count(*) AS n, sum(e.revenue) AS rev FROM events e JOIN users u ON u.user_id = e.user_id WHERE e.event_time >= '2026-03-01 00:00:00+00' AND e.event_time < '2026-04-01 00:00:00+00' GROUP BY u.plan ORDER BY u.plan;
