\getenv owner_password PG_OWNER_PASSWORD
\getenv app_password PG_APP_PASSWORD
BEGIN;
CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;
CREATE ROLE appointment_calendar_owner LOGIN PASSWORD :'owner_password';
CREATE ROLE appointment_calendar_app LOGIN PASSWORD :'app_password';
CREATE SCHEMA appointment_calendar AUTHORIZATION appointment_calendar_owner;
GRANT USAGE ON SCHEMA appointment_calendar TO appointment_calendar_app;
ALTER ROLE appointment_calendar_owner SET search_path=appointment_calendar,public,pg_catalog;
ALTER ROLE appointment_calendar_app SET search_path=appointment_calendar,pg_catalog;
ALTER ROLE appointment_calendar_app SET statement_timeout='5s';
ALTER ROLE appointment_calendar_app SET lock_timeout='3s';
COMMIT;
