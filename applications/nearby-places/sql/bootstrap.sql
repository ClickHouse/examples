\set ON_ERROR_STOP on
\getenv migration_password MIGRATION_PASSWORD
\getenv runtime_password APP_PASSWORD
SELECT length(:'migration_password') >= 24 AND length(:'runtime_password') >= 24
  AND :'migration_password' <> :'runtime_password' AS passwords_valid \gset
\if :passwords_valid
\else
  DO $$ BEGIN RAISE EXCEPTION 'Use distinct random passwords of at least 24 characters'; END $$;
\endif
BEGIN;
CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;
CREATE ROLE places_migration LOGIN PASSWORD :'migration_password';
CREATE ROLE places_reader LOGIN PASSWORD :'runtime_password';
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
SELECT format('REVOKE CREATE, TEMPORARY ON DATABASE %I FROM PUBLIC', current_database()) \gexec
CREATE SCHEMA nearby_places AUTHORIZATION places_migration;
REVOKE ALL ON SCHEMA nearby_places FROM PUBLIC;
GRANT USAGE ON SCHEMA nearby_places TO places_reader;
ALTER ROLE places_reader SET default_transaction_read_only = on;
ALTER ROLE places_reader SET statement_timeout = '2s';
ALTER ROLE places_reader SET idle_in_transaction_session_timeout = '5s';
COMMIT;
SELECT extname, extversion FROM pg_extension WHERE extname = 'postgis';
SELECT public.PostGIS_Full_Version();
