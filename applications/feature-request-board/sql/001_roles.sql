-- Run once as the service administrator using psql. Supply both passwords as
-- environment variables (see README). Use a dedicated example service/database.
\set ON_ERROR_STOP on
\getenv migration_password PG_MIGRATION_PASSWORD
\getenv app_password PG_APP_PASSWORD

BEGIN;

CREATE ROLE feature_board_migration LOGIN PASSWORD :'migration_password'
  NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
CREATE ROLE feature_board_app LOGIN PASSWORD :'app_password'
  NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;

CREATE SCHEMA feature_board AUTHORIZATION feature_board_migration;
GRANT CONNECT ON DATABASE :"DBNAME" TO feature_board_migration, feature_board_app;
-- The app must not inherit the public schema's create privilege.
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA feature_board TO feature_board_app;

ALTER ROLE feature_board_app SET statement_timeout = '10s';
ALTER ROLE feature_board_app SET lock_timeout = '5s';
ALTER ROLE feature_board_app SET idle_in_transaction_session_timeout = '10s';
COMMIT;
