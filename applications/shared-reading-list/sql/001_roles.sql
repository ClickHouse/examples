\getenv migration_password PG_MIGRATION_PASSWORD
\getenv app_password PG_APP_PASSWORD
CREATE ROLE reading_migration LOGIN PASSWORD :'migration_password';
CREATE ROLE reading_app LOGIN PASSWORD :'app_password';
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
CREATE SCHEMA reading AUTHORIZATION reading_migration;
CREATE SCHEMA reading_migrations AUTHORIZATION reading_migration;
GRANT USAGE ON SCHEMA reading TO reading_app;
