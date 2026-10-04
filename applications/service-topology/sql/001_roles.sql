\set ON_ERROR_STOP on
\getenv migration_password PG_MIGRATION_PASSWORD
\getenv app_password PG_APP_PASSWORD
CREATE ROLE topology_owner NOLOGIN;
CREATE ROLE topology_migration LOGIN PASSWORD :'migration_password';
CREATE ROLE topology_app LOGIN PASSWORD :'app_password';
GRANT topology_owner TO topology_migration;
CREATE SCHEMA service_topology AUTHORIZATION topology_owner;
REVOKE ALL ON SCHEMA service_topology FROM PUBLIC;
GRANT USAGE ON SCHEMA service_topology TO topology_app;
