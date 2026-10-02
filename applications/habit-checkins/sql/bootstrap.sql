\set ON_ERROR_STOP on
CREATE ROLE habit_migration LOGIN PASSWORD :'migration_password';
CREATE ROLE habit_app LOGIN PASSWORD :'app_password';
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
CREATE SCHEMA habits AUTHORIZATION habit_migration;
GRANT USAGE ON SCHEMA habits TO habit_app;
