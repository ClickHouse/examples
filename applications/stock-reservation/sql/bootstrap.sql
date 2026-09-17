-- Run ONCE as the service administrator with psql -X -v ON_ERROR_STOP=1.
-- Passwords come from the environment, not process arguments or committed files.
-- PG_MIGRATION_PASSWORD and PG_APP_PASSWORD must contain random generated passwords.
\getenv migration_password PG_MIGRATION_PASSWORD
\getenv app_password PG_APP_PASSWORD

BEGIN;

CREATE ROLE stock_reservation_owner NOLOGIN;
CREATE ROLE stock_reservation_migrator LOGIN NOINHERIT PASSWORD :'migration_password';
CREATE ROLE stock_reservation_app LOGIN NOINHERIT PASSWORD :'app_password';

-- The migrator must explicitly SET ROLE before changing the schema.
GRANT stock_reservation_owner TO stock_reservation_migrator;
GRANT stock_reservation_owner TO CURRENT_USER;
CREATE SCHEMA stock_reservation AUTHORIZATION stock_reservation_owner;
REVOKE ALL ON SCHEMA stock_reservation FROM PUBLIC;
GRANT CONNECT ON DATABASE :"DBNAME" TO stock_reservation_migrator, stock_reservation_app;

-- PostgreSQL enforces these limits on every runtime connection in the Bun pool.
ALTER ROLE stock_reservation_app SET statement_timeout = '5s';
ALTER ROLE stock_reservation_app SET lock_timeout = '3s';
ALTER ROLE stock_reservation_app SET idle_in_transaction_session_timeout = '10s';
ALTER ROLE stock_reservation_app SET search_path = pg_catalog;
ALTER ROLE stock_reservation_migrator SET statement_timeout = '30s';
ALTER ROLE stock_reservation_migrator SET lock_timeout = '5s';
ALTER ROLE stock_reservation_migrator SET idle_in_transaction_session_timeout = '30s';

COMMIT;
