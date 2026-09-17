-- DESTRUCTIVE: run as the service administrator only when finished with this
-- example. Stop the API first. This removes all example data, schema, and roles.
\set ON_ERROR_STOP on
BEGIN;
DROP SCHEMA IF EXISTS workshop_booking CASCADE;
-- Remove only this example's explicit CONNECT grants before dropping the roles.
SELECT format('REVOKE CONNECT ON DATABASE %I FROM workshop_booking_migrator, workshop_booking_app', current_database()) \gexec
DROP ROLE workshop_booking_app;
DROP ROLE workshop_booking_migrator;
DROP ROLE workshop_booking_owner;
COMMIT;
