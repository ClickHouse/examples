\set ON_ERROR_STOP on
\getenv migration_password PG_MIGRATION_PASSWORD
\getenv app_password PG_APP_PASSWORD
CREATE ROLE catalog_owner NOLOGIN;
CREATE ROLE catalog_migration LOGIN PASSWORD :'migration_password';
CREATE ROLE catalog_app LOGIN PASSWORD :'app_password';
GRANT catalog_owner TO catalog_migration;
CREATE SCHEMA product_catalog AUTHORIZATION catalog_owner;
REVOKE ALL ON SCHEMA product_catalog FROM PUBLIC;
GRANT USAGE ON SCHEMA product_catalog TO catalog_app;
