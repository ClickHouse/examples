SET search_path = ice, public;
\timing on
\echo RUN 1
SELECT user_id, sum(revenue) AS rev, count(*) AS n FROM events GROUP BY user_id ORDER BY rev DESC, user_id LIMIT 10;
\echo RUN 2
SELECT user_id, sum(revenue) AS rev, count(*) AS n FROM events GROUP BY user_id ORDER BY rev DESC, user_id LIMIT 10;
\echo RUN 3
SELECT user_id, sum(revenue) AS rev, count(*) AS n FROM events GROUP BY user_id ORDER BY rev DESC, user_id LIMIT 10;
\echo RUN 4
SELECT user_id, sum(revenue) AS rev, count(*) AS n FROM events GROUP BY user_id ORDER BY rev DESC, user_id LIMIT 10;
\echo RUN 5
SELECT user_id, sum(revenue) AS rev, count(*) AS n FROM events GROUP BY user_id ORDER BY rev DESC, user_id LIMIT 10;
\echo RUN 6
SELECT user_id, sum(revenue) AS rev, count(*) AS n FROM events GROUP BY user_id ORDER BY rev DESC, user_id LIMIT 10;
\echo RUN 7
SELECT user_id, sum(revenue) AS rev, count(*) AS n FROM events GROUP BY user_id ORDER BY rev DESC, user_id LIMIT 10;
\echo RUN 8
SELECT user_id, sum(revenue) AS rev, count(*) AS n FROM events GROUP BY user_id ORDER BY rev DESC, user_id LIMIT 10;
\echo RUN 9
SELECT user_id, sum(revenue) AS rev, count(*) AS n FROM events GROUP BY user_id ORDER BY rev DESC, user_id LIMIT 10;
\echo RUN 10
SELECT user_id, sum(revenue) AS rev, count(*) AS n FROM events GROUP BY user_id ORDER BY rev DESC, user_id LIMIT 10;
