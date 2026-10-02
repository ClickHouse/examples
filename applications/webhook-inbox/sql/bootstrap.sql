\set ON_ERROR_STOP on
\getenv migrator_password WEBHOOK_MIGRATOR_PASSWORD
\getenv receiver_password WEBHOOK_RECEIVER_PASSWORD
\getenv worker_password WEBHOOK_WORKER_PASSWORD
CREATE ROLE webhook_owner NOLOGIN;
CREATE ROLE webhook_migrator LOGIN PASSWORD :'migrator_password' NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE webhook_receiver LOGIN PASSWORD :'receiver_password' NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE webhook_worker LOGIN PASSWORD :'worker_password' NOSUPERUSER NOCREATEDB NOCREATEROLE;
GRANT webhook_owner TO webhook_migrator;
CREATE SCHEMA webhook AUTHORIZATION webhook_owner;
REVOKE ALL ON SCHEMA webhook FROM PUBLIC;
GRANT USAGE ON SCHEMA webhook TO webhook_receiver, webhook_worker;
ALTER ROLE webhook_receiver SET statement_timeout = '5s';
ALTER ROLE webhook_worker SET statement_timeout = '5s';
