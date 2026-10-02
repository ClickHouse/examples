DROP SCHEMA IF EXISTS reading CASCADE;
DROP SCHEMA IF EXISTS reading_migrations CASCADE;
DROP ROLE IF EXISTS reading_app;
REVOKE CREATE ON DATABASE postgres FROM reading_migration;
DROP ROLE IF EXISTS reading_migration;
