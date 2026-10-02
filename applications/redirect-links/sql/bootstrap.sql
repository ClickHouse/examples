\set ON_ERROR_STOP on
SELECT format('CREATE ROLE redirects_migration LOGIN PASSWORD %L', :'MIGRATION_PASSWORD')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'redirects_migration') \gexec
SELECT format('CREATE ROLE redirects_app LOGIN PASSWORD %L', :'APP_PASSWORD')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'redirects_app') \gexec
CREATE SCHEMA IF NOT EXISTS redirect_links AUTHORIZATION redirects_migration;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
SELECT format('REVOKE CREATE,TEMP ON DATABASE %I FROM PUBLIC', current_database()) \gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO redirects_migration,redirects_app', current_database()) \gexec
