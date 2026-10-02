-- Administrator only, on a dedicated disposable service with no existing directory roles.
\getenv owner_password PG_MIGRATION_PASSWORD
\getenv app_password PG_APP_PASSWORD
CREATE ROLE directory_owner LOGIN PASSWORD :'owner_password';
CREATE ROLE directory_app LOGIN PASSWORD :'app_password';
CREATE SCHEMA directory AUTHORIZATION directory_owner;
REVOKE ALL ON SCHEMA directory FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE CREATE, TEMP ON DATABASE postgres FROM PUBLIC;
GRANT CONNECT ON DATABASE postgres TO directory_owner, directory_app;
ALTER ROLE directory_owner SET search_path TO directory;
ALTER ROLE directory_app SET search_path TO directory;
