SET search_path = public;
\timing on
\echo WARMUP
SELECT country, date_trunc('day', event_time) AS day, count(*) AS n, sum(revenue) AS rev FROM events WHERE event_time >= '2026-02-01 00:00:00+00' AND event_time < '2026-03-01 00:00:00+00' AND event_type IN ('purchase', 'add_to_cart', 'checkout_start') GROUP BY country, day ORDER BY day, country;
