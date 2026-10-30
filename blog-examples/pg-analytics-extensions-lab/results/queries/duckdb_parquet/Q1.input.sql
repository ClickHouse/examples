SET duckdb.force_execution = true; SET duckdb.max_memory = 2048; SET search_path = duckpq, public;
\timing on
\echo RUN 1
SELECT count(*), sum(revenue) FROM events;
\echo RUN 2
SELECT count(*), sum(revenue) FROM events;
\echo RUN 3
SELECT count(*), sum(revenue) FROM events;
\echo RUN 4
SELECT count(*), sum(revenue) FROM events;
\echo RUN 5
SELECT count(*), sum(revenue) FROM events;
\echo RUN 6
SELECT count(*), sum(revenue) FROM events;
\echo RUN 7
SELECT count(*), sum(revenue) FROM events;
\echo RUN 8
SELECT count(*), sum(revenue) FROM events;
\echo RUN 9
SELECT count(*), sum(revenue) FROM events;
\echo RUN 10
SELECT count(*), sum(revenue) FROM events;
