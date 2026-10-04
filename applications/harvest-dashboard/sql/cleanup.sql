\set ON_ERROR_STOP on
-- Destructive: run only against this example's dedicated database.
BEGIN;
DROP SCHEMA harvest CASCADE;
DROP ROLE harvest_app;
REVOKE harvest_owner FROM harvest_migrator;
DROP ROLE harvest_migrator;
DROP ROLE harvest_owner;
COMMIT;
