\set ON_ERROR_STOP on
\getenv migration_password PG_MIGRATION_PASSWORD
\getenv app_password PG_APP_PASSWORD
BEGIN;
CREATE ROLE intake_owner NOLOGIN;
CREATE ROLE intake_migrator LOGIN PASSWORD :'migration_password';
GRANT intake_owner TO intake_migrator;
CREATE ROLE intake_app LOGIN PASSWORD :'app_password';
CREATE SCHEMA intake AUTHORIZATION intake_owner;
REVOKE ALL ON SCHEMA intake FROM PUBLIC;
GRANT USAGE ON SCHEMA intake TO intake_app;
COMMIT;
