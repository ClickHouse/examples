\set ON_ERROR_STOP on
\getenv migration_password MIGRATION_PASSWORD
\getenv app_password APP_PASSWORD
SELECT length(:'migration_password') >= 24 AND length(:'app_password') >= 24
  AND :'migration_password' <> :'app_password' AS passwords_valid \gset
\if :passwords_valid
\else
\echo Use two distinct role passwords of at least 24 characters
\quit 1
\endif
BEGIN;
CREATE ROLE polls_migration LOGIN PASSWORD :'migration_password';
CREATE ROLE polls_app LOGIN PASSWORD :'app_password';
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
SELECT format('REVOKE CREATE, TEMPORARY ON DATABASE %I FROM PUBLIC', current_database()) \gexec
CREATE SCHEMA poll_studio AUTHORIZATION polls_migration;
REVOKE ALL ON SCHEMA poll_studio FROM PUBLIC;
GRANT USAGE ON SCHEMA poll_studio TO polls_app;
ALTER ROLE polls_app SET statement_timeout = '5s';
ALTER ROLE polls_app SET lock_timeout = '3s';
ALTER ROLE polls_app SET idle_in_transaction_session_timeout = '5s';
COMMIT;
