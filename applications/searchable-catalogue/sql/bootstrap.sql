\set ON_ERROR_STOP on
\getenv migrator_password CATALOGUE_MIGRATOR_PASSWORD
\getenv reader_password CATALOGUE_READER_PASSWORD
CREATE ROLE catalogue_owner NOLOGIN;
CREATE ROLE catalogue_migrator LOGIN PASSWORD :'migrator_password' NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE catalogue_reader LOGIN PASSWORD :'reader_password' NOSUPERUSER NOCREATEDB NOCREATEROLE;
GRANT catalogue_owner TO catalogue_migrator;
CREATE SCHEMA catalogue AUTHORIZATION catalogue_owner;
REVOKE ALL ON SCHEMA catalogue FROM PUBLIC;
GRANT USAGE ON SCHEMA catalogue TO catalogue_reader;
ALTER ROLE catalogue_reader SET statement_timeout = '5s';
ALTER ROLE catalogue_reader SET default_transaction_read_only = on;
