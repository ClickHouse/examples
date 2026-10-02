\set ON_ERROR_STOP on
CREATE ROLE invites_owner NOLOGIN;
CREATE ROLE invites_migrator LOGIN PASSWORD :'migrator_password';
GRANT invites_owner TO invites_migrator;
CREATE ROLE invites_app LOGIN PASSWORD :'app_password';
GRANT CONNECT ON DATABASE postgres TO invites_migrator, invites_app;
CREATE SCHEMA invites AUTHORIZATION invites_owner;
REVOKE ALL ON SCHEMA invites FROM PUBLIC;
GRANT USAGE ON SCHEMA invites TO invites_migrator, invites_app;
ALTER ROLE invites_migrator SET search_path = invites;
ALTER ROLE invites_app SET search_path = invites;
