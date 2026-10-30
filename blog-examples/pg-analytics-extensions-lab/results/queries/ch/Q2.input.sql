SET search_path = ch, public;
\timing on
\echo RUN 1
SELECT event_type, count(*) AS n, sum(revenue) AS rev FROM events GROUP BY event_type ORDER BY event_type;
\echo RUN 2
SELECT event_type, count(*) AS n, sum(revenue) AS rev FROM events GROUP BY event_type ORDER BY event_type;
\echo RUN 3
SELECT event_type, count(*) AS n, sum(revenue) AS rev FROM events GROUP BY event_type ORDER BY event_type;
\echo RUN 4
SELECT event_type, count(*) AS n, sum(revenue) AS rev FROM events GROUP BY event_type ORDER BY event_type;
\echo RUN 5
SELECT event_type, count(*) AS n, sum(revenue) AS rev FROM events GROUP BY event_type ORDER BY event_type;
\echo RUN 6
SELECT event_type, count(*) AS n, sum(revenue) AS rev FROM events GROUP BY event_type ORDER BY event_type;
\echo RUN 7
SELECT event_type, count(*) AS n, sum(revenue) AS rev FROM events GROUP BY event_type ORDER BY event_type;
\echo RUN 8
SELECT event_type, count(*) AS n, sum(revenue) AS rev FROM events GROUP BY event_type ORDER BY event_type;
\echo RUN 9
SELECT event_type, count(*) AS n, sum(revenue) AS rev FROM events GROUP BY event_type ORDER BY event_type;
\echo RUN 10
SELECT event_type, count(*) AS n, sum(revenue) AS rev FROM events GROUP BY event_type ORDER BY event_type;
