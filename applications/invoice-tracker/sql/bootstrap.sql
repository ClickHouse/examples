\set ON_ERROR_STOP on
\getenv migrator_password INVOICE_MIGRATOR_PASSWORD
\getenv app_password INVOICE_APP_PASSWORD
CREATE ROLE invoice_migrator LOGIN PASSWORD :'migrator_password' NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE invoice_app LOGIN PASSWORD :'app_password' NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE SCHEMA invoice_tracker AUTHORIZATION invoice_migrator;
REVOKE ALL ON SCHEMA invoice_tracker FROM PUBLIC;
GRANT USAGE ON SCHEMA invoice_tracker TO invoice_app;
ALTER ROLE invoice_migrator SET search_path=invoice_tracker,public;
ALTER ROLE invoice_app SET search_path=invoice_tracker,public;
ALTER ROLE invoice_app SET statement_timeout='10s';
ALTER ROLE invoice_app SET lock_timeout='5s';
