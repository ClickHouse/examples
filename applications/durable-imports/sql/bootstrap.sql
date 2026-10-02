\set ON_ERROR_STOP on
\getenv migration_password MIGRATION_PASSWORD
\getenv api_password APP_PASSWORD
\getenv worker_password WORKER_PASSWORD
SELECT length(:'migration_password') >= 24 AND length(:'api_password') >= 24
  AND length(:'worker_password') >= 24 AND :'migration_password' <> :'api_password'
  AND :'migration_password' <> :'worker_password' AND :'api_password' <> :'worker_password'
  AS passwords_valid \gset
\if :passwords_valid
\else
  DO $$ BEGIN RAISE EXCEPTION 'Use distinct random passwords of at least 24 characters'; END $$;
\endif
BEGIN;
CREATE ROLE imports_migration LOGIN PASSWORD :'migration_password';
CREATE ROLE imports_api LOGIN PASSWORD :'api_password';
CREATE ROLE imports_worker LOGIN PASSWORD :'worker_password';
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
CREATE SCHEMA contact_imports AUTHORIZATION imports_migration;
CREATE SCHEMA import_jobs AUTHORIZATION imports_migration;
REVOKE ALL ON SCHEMA contact_imports, import_jobs FROM PUBLIC;
GRANT USAGE ON SCHEMA contact_imports, import_jobs TO imports_api, imports_worker;
ALTER ROLE imports_api SET statement_timeout = '15s';
ALTER ROLE imports_api SET lock_timeout = '5s';
ALTER ROLE imports_api SET idle_in_transaction_session_timeout = '15s';
ALTER ROLE imports_worker SET statement_timeout = '15s';
ALTER ROLE imports_worker SET lock_timeout = '5s';
ALTER ROLE imports_worker SET idle_in_transaction_session_timeout = '25s';
COMMIT;
