\getenv migration_password PG_MIGRATION_PASSWORD
\getenv app_password PG_APP_PASSWORD
CREATE ROLE tracker_migration LOGIN PASSWORD :'migration_password';
CREATE ROLE tracker_member NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE tracker_api LOGIN NOINHERIT NOSUPERUSER NOBYPASSRLS PASSWORD :'app_password';
GRANT tracker_member TO tracker_api;
GRANT CONNECT ON DATABASE postgres TO tracker_api,tracker_migration;
GRANT CREATE ON DATABASE postgres TO tracker_migration;
