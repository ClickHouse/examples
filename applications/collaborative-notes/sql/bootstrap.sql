-- Run once as the dedicated service administrator. psql receives private variables.
\set ON_ERROR_STOP on
CREATE ROLE notes_owner LOGIN NOINHERIT PASSWORD :'owner_password';
CREATE ROLE notes_runtime LOGIN NOINHERIT PASSWORD :'runtime_password';
REVOKE CREATE, TEMPORARY ON DATABASE postgres FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT CONNECT ON DATABASE postgres TO notes_owner, notes_runtime;
GRANT CREATE ON DATABASE postgres TO notes_owner;
CREATE SCHEMA notes AUTHORIZATION notes_owner;
