\getenv owner_password PG_MIGRATION_PASSWORD
\getenv app_password PG_APP_PASSWORD
CREATE ROLE playlist_owner LOGIN PASSWORD :'owner_password';
CREATE ROLE playlist_app LOGIN PASSWORD :'app_password';
CREATE SCHEMA playlist_api AUTHORIZATION playlist_owner;
REVOKE ALL ON SCHEMA playlist_api FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE CREATE, TEMP ON DATABASE postgres FROM PUBLIC;
GRANT CONNECT ON DATABASE postgres TO playlist_owner,playlist_app;
ALTER ROLE playlist_owner SET search_path TO playlist_api,public;
ALTER ROLE playlist_app SET search_path TO playlist_api,public;
