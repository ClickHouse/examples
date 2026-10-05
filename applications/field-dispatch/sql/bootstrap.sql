\set ON_ERROR_STOP on
\getenv migration_password PG_MIGRATION_PASSWORD
\getenv app_password PG_APP_PASSWORD
BEGIN;
CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;
CREATE ROLE dispatch_owner NOLOGIN;
CREATE ROLE dispatch_migrator LOGIN PASSWORD :'migration_password';
GRANT dispatch_owner TO dispatch_migrator;
CREATE ROLE dispatch_app LOGIN PASSWORD :'app_password';
CREATE SCHEMA dispatch AUTHORIZATION dispatch_owner;
REVOKE ALL ON SCHEMA dispatch FROM PUBLIC;
GRANT USAGE ON SCHEMA dispatch, public TO dispatch_app;
COMMIT;
