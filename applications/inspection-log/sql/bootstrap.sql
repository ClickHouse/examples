-- Cloud administrator; password variables supplied by private setup shell.
SELECT 'CREATE ROLE inspection_owner NOLOGIN'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'inspection_owner') \gexec
SELECT 'CREATE ROLE inspection_migrator LOGIN NOINHERIT'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'inspection_migrator') \gexec
SELECT 'CREATE ROLE inspection_app LOGIN NOINHERIT'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'inspection_app') \gexec
ALTER ROLE inspection_migrator PASSWORD :'migrator_password';
ALTER ROLE inspection_app PASSWORD :'app_password';
GRANT inspection_owner TO inspection_migrator;
CREATE SCHEMA IF NOT EXISTS inspection_api AUTHORIZATION inspection_owner;
REVOKE ALL ON SCHEMA inspection_api FROM PUBLIC;
GRANT USAGE ON SCHEMA inspection_api TO inspection_app;
SELECT format('REVOKE TEMPORARY ON DATABASE %I FROM PUBLIC', current_database()) \gexec
ALTER ROLE inspection_app SET search_path TO inspection_api, pg_catalog;
ALTER ROLE inspection_app SET statement_timeout TO '8s';
ALTER ROLE inspection_app SET lock_timeout TO '3s';
ALTER ROLE inspection_app SET idle_in_transaction_session_timeout TO '10s';
