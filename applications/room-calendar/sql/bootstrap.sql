\set ON_ERROR_STOP on
-- Administrator only, once for an empty owned fixture.
BEGIN;
CREATE ROLE calendar_owner NOLOGIN;
CREATE ROLE calendar_migrator LOGIN NOINHERIT PASSWORD :'migrator_password';
CREATE ROLE calendar_app LOGIN NOINHERIT PASSWORD :'app_password';
GRANT calendar_owner TO calendar_migrator;
CREATE SCHEMA calendar AUTHORIZATION calendar_owner;
CREATE SCHEMA calendar_ext AUTHORIZATION calendar_owner;
CREATE EXTENSION btree_gist WITH SCHEMA calendar_ext;
REVOKE ALL ON SCHEMA calendar,calendar_ext FROM PUBLIC;
GRANT USAGE ON SCHEMA calendar TO calendar_app;
ALTER ROLE calendar_migrator SET search_path TO calendar,calendar_ext,pg_catalog;
ALTER ROLE calendar_app SET search_path TO calendar,pg_catalog;
ALTER ROLE calendar_app SET statement_timeout='5s';
ALTER ROLE calendar_app SET lock_timeout='2s';
ALTER ROLE calendar_app SET timezone='UTC';
COMMIT;
