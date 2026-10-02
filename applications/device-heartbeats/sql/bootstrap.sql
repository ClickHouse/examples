\set ON_ERROR_STOP on
SELECT format('CREATE ROLE heartbeats_migration LOGIN PASSWORD %L', :'MIGRATION_PASSWORD')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname='heartbeats_migration') \gexec
SELECT format('CREATE ROLE heartbeats_app LOGIN PASSWORD %L', :'APP_PASSWORD')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname='heartbeats_app') \gexec
CREATE SCHEMA IF NOT EXISTS heartbeats AUTHORIZATION heartbeats_migration;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
SELECT format('REVOKE CREATE,TEMP ON DATABASE %I FROM PUBLIC',current_database()) \gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO heartbeats_migration,heartbeats_app',current_database()) \gexec
