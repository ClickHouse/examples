\set ON_ERROR_STOP on
SELECT format('CREATE ROLE transfers_migration LOGIN PASSWORD %L', :'MIGRATION_PASSWORD')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'transfers_migration') \gexec
SELECT format('CREATE ROLE transfers_app LOGIN PASSWORD %L', :'APP_PASSWORD')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'transfers_app') \gexec
CREATE SCHEMA IF NOT EXISTS transfers AUTHORIZATION transfers_migration;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
SELECT format('REVOKE CREATE, TEMP ON DATABASE %I FROM PUBLIC', current_database()) \gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO transfers_migration, transfers_app', current_database()) \gexec
