\set ON_ERROR_STOP on
-- Run as the service administrator. Passwords are supplied as psql variables.
CREATE ROLE expense_migration LOGIN PASSWORD :'migration_password';
CREATE ROLE expense_app LOGIN PASSWORD :'app_password';
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
CREATE SCHEMA expenses AUTHORIZATION expense_migration;
GRANT USAGE ON SCHEMA expenses TO expense_app;
