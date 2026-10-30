\timing on
CREATE EXTENSION IF NOT EXISTS pg_lake CASCADE;
SELECT extname, extversion FROM pg_extension ORDER BY 1;
SHOW pg_lake_iceberg.default_location_prefix;
DROP SCHEMA IF EXISTS ice CASCADE;  -- note: schema name "lake" is taken by the pg_lake extension itself
CREATE SCHEMA ice;
-- Iceberg copies of the heap tables, written as Parquet to S3 (SeaweedFS) by pgduck_server
CREATE TABLE ice.events USING iceberg AS SELECT * FROM public.events;
CREATE TABLE ice.users  USING iceberg AS SELECT * FROM public.users;
SELECT count(*) FROM ice.events;
SELECT count(*) FROM ice.users;
