\set ON_ERROR_STOP on
\getenv app_password PG_APP_PASSWORD
\getenv migration_password PG_MIGRATION_PASSWORD
\getenv cdc_password PG_CDC_PASSWORD

BEGIN;

-- Run as the service administrator. Existing passwords are never reset here.
SELECT format('CREATE ROLE link_shortener_migration LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD %L', :'migration_password')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'link_shortener_migration')
\gexec
SELECT format('CREATE ROLE link_shortener_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD %L', :'app_password')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'link_shortener_app')
\gexec
SELECT format('CREATE ROLE link_shortener_cdc LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE REPLICATION PASSWORD %L', :'cdc_password')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'link_shortener_cdc')
\gexec

-- The administrator must be able to publish migration-owned tables.
GRANT link_shortener_migration TO CURRENT_USER;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE, CREATE ON SCHEMA public TO link_shortener_migration;
GRANT USAGE ON SCHEMA public TO link_shortener_app, link_shortener_cdc;
SELECT format('GRANT CONNECT ON DATABASE %I TO link_shortener_migration, link_shortener_app, link_shortener_cdc', current_database())
\gexec

COMMIT;
