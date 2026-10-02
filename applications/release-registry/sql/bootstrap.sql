\set ON_ERROR_STOP on
\getenv migrator_password REGISTRY_MIGRATOR_PASSWORD
\getenv app_password REGISTRY_APP_PASSWORD
CREATE ROLE registry_owner NOLOGIN;
CREATE ROLE registry_migrator LOGIN PASSWORD :'migrator_password' NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE registry_app LOGIN PASSWORD :'app_password' NOSUPERUSER NOCREATEDB NOCREATEROLE;
GRANT registry_owner TO registry_migrator;
CREATE SCHEMA registry AUTHORIZATION registry_owner;
REVOKE ALL ON SCHEMA registry FROM PUBLIC;
GRANT USAGE ON SCHEMA registry TO registry_app;
ALTER ROLE registry_app SET statement_timeout = '5s';
