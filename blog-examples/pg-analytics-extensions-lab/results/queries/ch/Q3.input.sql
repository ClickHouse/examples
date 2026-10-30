SET search_path = ch, public;
\timing on
\echo RUN 1
SELECT country, date_trunc('day', event_time) AS day, count(*) AS n, sum(revenue) AS rev FROM events WHERE event_time >= '2026-02-01 00:00:00+00' AND event_time < '2026-03-01 00:00:00+00' AND event_type IN ('purchase', 'add_to_cart', 'checkout_start') GROUP BY country, day ORDER BY day, country;
\echo RUN 2
SELECT country, date_trunc('day', event_time) AS day, count(*) AS n, sum(revenue) AS rev FROM events WHERE event_time >= '2026-02-01 00:00:00+00' AND event_time < '2026-03-01 00:00:00+00' AND event_type IN ('purchase', 'add_to_cart', 'checkout_start') GROUP BY country, day ORDER BY day, country;
\echo RUN 3
SELECT country, date_trunc('day', event_time) AS day, count(*) AS n, sum(revenue) AS rev FROM events WHERE event_time >= '2026-02-01 00:00:00+00' AND event_time < '2026-03-01 00:00:00+00' AND event_type IN ('purchase', 'add_to_cart', 'checkout_start') GROUP BY country, day ORDER BY day, country;
\echo RUN 4
SELECT country, date_trunc('day', event_time) AS day, count(*) AS n, sum(revenue) AS rev FROM events WHERE event_time >= '2026-02-01 00:00:00+00' AND event_time < '2026-03-01 00:00:00+00' AND event_type IN ('purchase', 'add_to_cart', 'checkout_start') GROUP BY country, day ORDER BY day, country;
\echo RUN 5
SELECT country, date_trunc('day', event_time) AS day, count(*) AS n, sum(revenue) AS rev FROM events WHERE event_time >= '2026-02-01 00:00:00+00' AND event_time < '2026-03-01 00:00:00+00' AND event_type IN ('purchase', 'add_to_cart', 'checkout_start') GROUP BY country, day ORDER BY day, country;
\echo RUN 6
SELECT country, date_trunc('day', event_time) AS day, count(*) AS n, sum(revenue) AS rev FROM events WHERE event_time >= '2026-02-01 00:00:00+00' AND event_time < '2026-03-01 00:00:00+00' AND event_type IN ('purchase', 'add_to_cart', 'checkout_start') GROUP BY country, day ORDER BY day, country;
\echo RUN 7
SELECT country, date_trunc('day', event_time) AS day, count(*) AS n, sum(revenue) AS rev FROM events WHERE event_time >= '2026-02-01 00:00:00+00' AND event_time < '2026-03-01 00:00:00+00' AND event_type IN ('purchase', 'add_to_cart', 'checkout_start') GROUP BY country, day ORDER BY day, country;
\echo RUN 8
SELECT country, date_trunc('day', event_time) AS day, count(*) AS n, sum(revenue) AS rev FROM events WHERE event_time >= '2026-02-01 00:00:00+00' AND event_time < '2026-03-01 00:00:00+00' AND event_type IN ('purchase', 'add_to_cart', 'checkout_start') GROUP BY country, day ORDER BY day, country;
\echo RUN 9
SELECT country, date_trunc('day', event_time) AS day, count(*) AS n, sum(revenue) AS rev FROM events WHERE event_time >= '2026-02-01 00:00:00+00' AND event_time < '2026-03-01 00:00:00+00' AND event_type IN ('purchase', 'add_to_cart', 'checkout_start') GROUP BY country, day ORDER BY day, country;
\echo RUN 10
SELECT country, date_trunc('day', event_time) AS day, count(*) AS n, sum(revenue) AS rev FROM events WHERE event_time >= '2026-02-01 00:00:00+00' AND event_time < '2026-03-01 00:00:00+00' AND event_type IN ('purchase', 'add_to_cart', 'checkout_start') GROUP BY country, day ORDER BY day, country;
