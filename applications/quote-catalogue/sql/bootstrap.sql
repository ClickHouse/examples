\getenv owner_password PG_OWNER_PASSWORD
\getenv app_password PG_APP_PASSWORD
BEGIN;
CREATE ROLE quote_catalogue_owner LOGIN PASSWORD :'owner_password';
CREATE ROLE quote_catalogue_app LOGIN PASSWORD :'app_password';
CREATE SCHEMA quote_catalogue AUTHORIZATION quote_catalogue_owner;
GRANT USAGE ON SCHEMA quote_catalogue TO quote_catalogue_app;
ALTER ROLE quote_catalogue_owner SET search_path = quote_catalogue, pg_catalog;
ALTER ROLE quote_catalogue_app SET search_path = quote_catalogue, pg_catalog;
ALTER ROLE quote_catalogue_app SET statement_timeout = '5s';
ALTER ROLE quote_catalogue_app SET lock_timeout = '3s';
COMMIT;
