-- Run with the Cloud administrator and psql variables for the two passwords.
SELECT 'CREATE ROLE revision_owner NOLOGIN'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'revision_owner') \gexec
SELECT 'CREATE ROLE revision_migrator LOGIN NOINHERIT'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'revision_migrator') \gexec
SELECT 'CREATE ROLE revision_app LOGIN NOINHERIT'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'revision_app') \gexec
ALTER ROLE revision_migrator PASSWORD :'migrator_password';
ALTER ROLE revision_app PASSWORD :'app_password';
GRANT revision_owner TO revision_migrator;
CREATE SCHEMA IF NOT EXISTS revision_api AUTHORIZATION revision_owner;
REVOKE ALL ON SCHEMA revision_api FROM PUBLIC;
GRANT USAGE ON SCHEMA revision_api TO revision_app;
ALTER ROLE revision_app SET search_path TO revision_api, pg_catalog;
ALTER ROLE revision_app SET statement_timeout TO '8s';
ALTER ROLE revision_app SET lock_timeout TO '3s';
ALTER ROLE revision_app SET idle_in_transaction_session_timeout TO '10s';
ALTER ROLE revision_migrator SET statement_timeout TO '15s';
