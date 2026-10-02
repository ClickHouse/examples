\set ON_ERROR_STOP on
\getenv migrator_password SUPPORT_MIGRATOR_PASSWORD
\getenv app_password SUPPORT_APP_PASSWORD
CREATE ROLE support_desk_migrator LOGIN PASSWORD :'migrator_password' NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE support_desk_app LOGIN PASSWORD :'app_password' NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE SCHEMA support_desk AUTHORIZATION support_desk_migrator;
REVOKE ALL ON SCHEMA support_desk FROM PUBLIC;
GRANT USAGE ON SCHEMA support_desk TO support_desk_app;
ALTER ROLE support_desk_migrator SET search_path = support_desk, public;
ALTER ROLE support_desk_app SET search_path = support_desk, public;
