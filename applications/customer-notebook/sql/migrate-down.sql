\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE notebook_owner;
SELECT pg_advisory_xact_lock(887002);
SELECT EXISTS(SELECT 1 FROM notebook.schema_migrations WHERE version=1) AS apply \gset
\if :apply
  \ir 001-down.sql
  DELETE FROM notebook.schema_migrations WHERE version=1;
\endif
COMMIT;
