\set ON_ERROR_STOP on
\getenv migrator_password EQUIPMENT_MIGRATOR_PASSWORD
\getenv app_password EQUIPMENT_APP_PASSWORD
CREATE ROLE equipment_migrator LOGIN PASSWORD :'migrator_password' NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE equipment_app LOGIN PASSWORD :'app_password' NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE SCHEMA equipment AUTHORIZATION equipment_migrator;
REVOKE ALL ON SCHEMA equipment FROM PUBLIC;
GRANT USAGE ON SCHEMA equipment TO equipment_app;
ALTER ROLE equipment_migrator SET search_path = equipment, public;
ALTER ROLE equipment_app SET search_path = equipment, public;
