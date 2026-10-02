\set ON_ERROR_STOP on
\getenv migrator_password SHIPMENTS_MIGRATOR_PASSWORD
\getenv app_password SHIPMENTS_APP_PASSWORD
\getenv cdc_password SHIPMENTS_CDC_PASSWORD
BEGIN;
CREATE ROLE shipments_owner NOLOGIN;
CREATE ROLE shipments_migrator LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD :'migrator_password';
CREATE ROLE shipments_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD :'app_password';
CREATE ROLE shipments_cdc LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE REPLICATION PASSWORD :'cdc_password';
GRANT shipments_owner TO shipments_migrator;
GRANT shipments_owner TO CURRENT_USER;
CREATE SCHEMA shipments AUTHORIZATION shipments_owner;
REVOKE ALL ON SCHEMA shipments FROM PUBLIC;
GRANT USAGE ON SCHEMA shipments TO shipments_app, shipments_cdc;
ALTER ROLE shipments_app SET statement_timeout = '20s';
COMMIT;
