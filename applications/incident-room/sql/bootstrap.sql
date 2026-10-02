\set ON_ERROR_STOP on
CREATE ROLE incident_migration LOGIN PASSWORD :'migration_password';
CREATE ROLE incident_app LOGIN PASSWORD :'app_password';
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
CREATE SCHEMA incident_room AUTHORIZATION incident_migration;
GRANT USAGE ON SCHEMA incident_room TO incident_app;
