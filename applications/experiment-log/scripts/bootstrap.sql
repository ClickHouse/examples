-- Administrator only; dedicated service.
\getenv owner_password PG_MIGRATION_PASSWORD
\getenv app_password PG_APP_PASSWORD
CREATE ROLE experiment_owner LOGIN PASSWORD :'owner_password';
CREATE ROLE experiment_app LOGIN PASSWORD :'app_password';
CREATE SCHEMA experiment_log AUTHORIZATION experiment_owner;
REVOKE ALL ON SCHEMA experiment_log FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE CREATE, TEMP ON DATABASE postgres FROM PUBLIC;
GRANT CONNECT ON DATABASE postgres TO experiment_owner, experiment_app;
ALTER ROLE experiment_owner SET search_path TO experiment_log, public;
ALTER ROLE experiment_app SET search_path TO experiment_log, public;
