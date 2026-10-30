SET search_path = ch, public;
\timing on
\echo RUN 1
SELECT count(*), sum(revenue) FROM events;
\echo RUN 2
SELECT count(*), sum(revenue) FROM events;
\echo RUN 3
SELECT count(*), sum(revenue) FROM events;
\echo RUN 4
SELECT count(*), sum(revenue) FROM events;
