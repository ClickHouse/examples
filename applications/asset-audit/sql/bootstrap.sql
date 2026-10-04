\set ON_ERROR_STOP on
\getenv owner_password PG_OWNER_PASSWORD
\getenv app_password PG_APP_PASSWORD
BEGIN;
CREATE ROLE asset_audit_owner LOGIN PASSWORD :'owner_password';
CREATE ROLE asset_audit_app LOGIN PASSWORD :'app_password';
CREATE SCHEMA asset_audit AUTHORIZATION asset_audit_owner;
GRANT USAGE ON SCHEMA asset_audit TO asset_audit_app;
ALTER ROLE asset_audit_owner SET search_path = asset_audit, pg_catalog;
ALTER ROLE asset_audit_app SET search_path = asset_audit, pg_catalog;
ALTER ROLE asset_audit_app SET statement_timeout = '5s';
ALTER ROLE asset_audit_app SET lock_timeout = '3s';
COMMIT;
