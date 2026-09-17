-- Run once as the service administrator, before Alembic.
-- psql -X --set=ON_ERROR_STOP=1 --file=sql/bootstrap.sql
-- Passwords come from the environment, never from command-line arguments.
\set ON_ERROR_STOP on
\getenv migrator_password WORKSHOP_MIGRATOR_PASSWORD
\getenv app_password WORKSHOP_APP_PASSWORD
\if :{?migrator_password}
\else
  DO $$ BEGIN RAISE EXCEPTION 'Set WORKSHOP_MIGRATOR_PASSWORD before running bootstrap.sql.'; END $$;
\endif
\if :{?app_password}
\else
  DO $$ BEGIN RAISE EXCEPTION 'Set WORKSHOP_APP_PASSWORD before running bootstrap.sql.'; END $$;
\endif
SELECT length(:'migrator_password') >= 24 AND length(:'app_password') >= 24
       AND :'migrator_password' <> :'app_password' AS passwords_valid \gset
\if :passwords_valid
\else
  DO $$ BEGIN RAISE EXCEPTION 'Use distinct, randomly generated passwords of at least 24 characters.'; END $$;
\endif

BEGIN;

-- This is deliberately run-once: existing names abort the transaction instead
-- of changing ownership or rotating credentials for an unrelated application.
-- New roles have no superuser, database-create, role-create, replication or
-- bypass-RLS privileges by default; no superuser-only ALTER is necessary.
CREATE ROLE workshop_booking_owner NOLOGIN;
CREATE ROLE workshop_booking_migrator LOGIN NOINHERIT;
CREATE ROLE workshop_booking_app LOGIN NOINHERIT;

SELECT format('ALTER ROLE workshop_booking_migrator PASSWORD %L', :'migrator_password') \gexec
SELECT format('ALTER ROLE workshop_booking_app PASSWORD %L', :'app_password') \gexec

GRANT workshop_booking_owner TO workshop_booking_migrator;
-- The administrator needs membership to create a schema owned by this role.
GRANT workshop_booking_owner TO CURRENT_USER;
SELECT format('GRANT CONNECT ON DATABASE %I TO workshop_booking_migrator, workshop_booking_app', current_database()) \gexec

CREATE SCHEMA workshop_booking AUTHORIZATION workshop_booking_owner;
REVOKE ALL ON SCHEMA workshop_booking FROM PUBLIC;

ALTER ROLE workshop_booking_app SET search_path = pg_catalog, workshop_booking;
ALTER ROLE workshop_booking_app SET statement_timeout = '10s';
ALTER ROLE workshop_booking_app SET lock_timeout = '5s';
ALTER ROLE workshop_booking_app SET idle_in_transaction_session_timeout = '15s';
ALTER ROLE workshop_booking_migrator SET search_path = pg_catalog, workshop_booking;

COMMIT;

-- A runtime role can inherit permissions granted to PUBLIC. Review these before
-- sharing the database with another application; this script does not revoke
-- privileges that other applications may rely on.
SELECT has_schema_privilege('workshop_booking_app', 'public', 'CREATE')
       AS runtime_can_create_in_public;
