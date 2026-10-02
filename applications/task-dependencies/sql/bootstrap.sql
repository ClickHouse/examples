\set ON_ERROR_STOP on
\getenv owner_password TASKS_OWNER_PASSWORD
\getenv runtime_password TASKS_RUNTIME_PASSWORD
SELECT 'CREATE ROLE tasks_owner LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE' WHERE NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='tasks_owner') \gexec
SELECT 'CREATE ROLE tasks_runtime LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE' WHERE NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='tasks_runtime') \gexec
ALTER ROLE tasks_owner PASSWORD :'owner_password';
ALTER ROLE tasks_runtime PASSWORD :'runtime_password';
CREATE SCHEMA IF NOT EXISTS task_dependencies AUTHORIZATION tasks_owner;
SELECT format('REVOKE CREATE, TEMP ON DATABASE %I FROM PUBLIC',current_database()) \gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO tasks_owner, tasks_runtime',current_database()) \gexec
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
ALTER ROLE tasks_runtime SET statement_timeout='10s';
ALTER ROLE tasks_runtime SET lock_timeout='5s';
ALTER ROLE tasks_runtime SET idle_in_transaction_session_timeout='15s';
