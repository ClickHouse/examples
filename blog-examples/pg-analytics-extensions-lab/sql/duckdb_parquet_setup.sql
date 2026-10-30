\timing on
-- Optional pg_duckdb variant: export the heap tables to local Parquet with DuckDB, then query the files.
SET duckdb.force_execution = true;
COPY (SELECT * FROM public.events) TO '/var/lib/postgresql/data/lab_events.parquet' (FORMAT parquet);
COPY (SELECT * FROM public.users)  TO '/var/lib/postgresql/data/lab_users.parquet'  (FORMAT parquet);
DROP SCHEMA IF EXISTS duckpq CASCADE;
CREATE SCHEMA duckpq;
CREATE VIEW duckpq.events AS
  SELECT r['event_id']::bigint AS event_id, r['event_time']::timestamptz AS event_time, r['user_id']::bigint AS user_id,
         r['event_type']::text AS event_type, r['country']::text AS country, r['url']::text AS url,
         r['duration_ms']::int AS duration_ms, r['revenue']::numeric(10,2) AS revenue
  FROM read_parquet('/var/lib/postgresql/data/lab_events.parquet') r;
CREATE VIEW duckpq.users AS
  SELECT r['user_id']::bigint AS user_id, r['signup_date']::date AS signup_date, r['plan']::text AS plan, r['country']::text AS country
  FROM read_parquet('/var/lib/postgresql/data/lab_users.parquet') r;
SELECT count(*) FROM duckpq.events;
