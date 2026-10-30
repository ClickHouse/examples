SELECT event_type, count(*), sum(revenue) FROM lab.events GROUP BY event_type ORDER BY event_type ASC NULLS LAST
SELECT user_id, sum(revenue), count(*) FROM lab.events GROUP BY user_id ORDER BY sum(revenue) DESC NULLS FIRST, user_id ASC NULLS LAST LIMIT 10
SELECT count(*), sum(revenue) FROM lab.events
SELECT country, toStartOfDay(event_time), count(*), sum(revenue) FROM lab.events WHERE ((event_time >= '2026-02-01 00:00:00')) AND ((event_time < '2026-03-01 00:00:00')) AND ((event_type IN ('purchase','add_to_cart','checkout_start'))) GROUP BY country, (toStartOfDay(event_time)) ORDER BY toStartOfDay(event_time) ASC NULLS LAST, country ASC NULLS LAST
SELECT r2.plan, count(*), sum(r1.revenue) FROM  lab.events r1 ALL INNER JOIN lab.users r2 ON (((r1.user_id = r2.user_id))) WHERE ((r1.event_time >= '2026-03-01 00:00:00')) AND ((r1.event_time < '2026-04-01 00:00:00')) GROUP BY r2.plan ORDER BY r2.plan ASC NULLS LAST
SELECT count(DISTINCT user_id) FROM lab.events
