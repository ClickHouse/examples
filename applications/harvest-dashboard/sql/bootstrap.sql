\set ON_ERROR_STOP on
\getenv migration_password PG_MIGRATION_PASSWORD
\getenv app_password PG_APP_PASSWORD
BEGIN;
CREATE ROLE harvest_owner NOLOGIN;
CREATE ROLE harvest_migrator LOGIN PASSWORD :'migration_password';
GRANT harvest_owner TO harvest_migrator;
CREATE ROLE harvest_app LOGIN PASSWORD :'app_password';
CREATE SCHEMA harvest AUTHORIZATION harvest_owner;
REVOKE ALL ON SCHEMA harvest FROM PUBLIC;
GRANT USAGE ON SCHEMA harvest TO harvest_app;
COMMIT;
