\set ON_ERROR_STOP on
\getenv owner_password CHECKLIST_OWNER_PASSWORD
\getenv authenticator_password CHECKLIST_AUTH_PASSWORD

SELECT 'CREATE ROLE checklist_owner LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'checklist_owner') \gexec
SELECT 'CREATE ROLE checklist_authenticator LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'checklist_authenticator') \gexec
SELECT 'CREATE ROLE checklist_north NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'checklist_north') \gexec
SELECT 'CREATE ROLE checklist_south NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'checklist_south') \gexec

ALTER ROLE checklist_owner PASSWORD :'owner_password';
ALTER ROLE checklist_authenticator PASSWORD :'authenticator_password';
ALTER ROLE checklist_authenticator NOINHERIT;
GRANT checklist_north, checklist_south TO checklist_authenticator;
REVOKE checklist_owner FROM checklist_authenticator;
SELECT format('GRANT CONNECT ON DATABASE %I TO checklist_owner, checklist_authenticator', current_database()) \gexec
SELECT format('REVOKE CREATE, TEMPORARY ON DATABASE %I FROM PUBLIC', current_database()) \gexec
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
CREATE SCHEMA IF NOT EXISTS checklist_storage AUTHORIZATION checklist_owner;
CREATE SCHEMA IF NOT EXISTS checklist_api AUTHORIZATION checklist_owner;
REVOKE ALL ON SCHEMA checklist_storage, checklist_api FROM PUBLIC;
ALTER ROLE checklist_authenticator SET statement_timeout = '10s';
ALTER ROLE checklist_authenticator SET lock_timeout = '5s';
ALTER ROLE checklist_authenticator SET idle_in_transaction_session_timeout = '15s';
ALTER ROLE checklist_north SET statement_timeout = '10s';
ALTER ROLE checklist_north SET lock_timeout = '5s';
ALTER ROLE checklist_south SET statement_timeout = '10s';
ALTER ROLE checklist_south SET lock_timeout = '5s';
