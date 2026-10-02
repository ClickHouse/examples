\set ON_ERROR_STOP on
-- Run as the owned service administrator. Passwords arrive as psql variables.
CREATE ROLE notebook_owner NOLOGIN;
CREATE ROLE notebook_migrator LOGIN NOINHERIT PASSWORD :'migrator_password';
CREATE ROLE notebook_app LOGIN NOINHERIT PASSWORD :'app_password';
CREATE ROLE notebook_report LOGIN NOINHERIT PASSWORD :'report_password';
GRANT notebook_owner TO notebook_migrator;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
CREATE SCHEMA notebook AUTHORIZATION notebook_owner;
GRANT USAGE ON SCHEMA notebook TO notebook_app;
ALTER ROLE notebook_app SET search_path TO notebook,pg_catalog;
ALTER ROLE notebook_app SET statement_timeout='5s';
ALTER ROLE notebook_app SET lock_timeout='2s';
ALTER ROLE notebook_report SET statement_timeout='12s';
ALTER ROLE notebook_report SET lock_timeout='2s';
ALTER ROLE notebook_report SET default_transaction_read_only=on;
