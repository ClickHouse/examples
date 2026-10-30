SET search_path = ch, public;
\timing on
\echo RUN 1
SELECT count(*), sum(revenue) FROM events;
