SET duckdb.force_execution = true; SET duckdb.max_memory = 2048; SET search_path = duckpq, public;
\timing on
\echo RUN 1
SELECT country, date_trunc('day', event_time) AS day, count(*) AS n, sum(revenue) AS rev FROM events WHERE event_time >= '2026-02-01 00:00:00+00' AND event_time < '2026-03-01 00:00:00+00' AND event_type IN ('purchase', 'add_to_cart', 'checkout_start') GROUP BY country, day ORDER BY day, country;
\echo RUN 2
SELECT country, date_trunc('day', event_time) AS day, count(*) AS n, sum(revenue) AS rev FROM events WHERE event_time >= '2026-02-01 00:00:00+00' AND event_time < '2026-03-01 00:00:00+00' AND event_type IN ('purchase', 'add_to_cart', 'checkout_start') GROUP BY country, day ORDER BY day, country;
\echo RUN 3
SELECT country, date_trunc('day', event_time) AS day, count(*) AS n, sum(revenue) AS rev FROM events WHERE event_time >= '2026-02-01 00:00:00+00' AND event_time < '2026-03-01 00:00:00+00' AND event_type IN ('purchase', 'add_to_cart', 'checkout_start') GROUP BY country, day ORDER BY day, country;
\echo RUN 4
SELECT country, date_trunc('day', event_time) AS day, count(*) AS n, sum(revenue) AS rev FROM events WHERE event_time >= '2026-02-01 00:00:00+00' AND event_time < '2026-03-01 00:00:00+00' AND event_type IN ('purchase', 'add_to_cart', 'checkout_start') GROUP BY country, day ORDER BY day, country;
