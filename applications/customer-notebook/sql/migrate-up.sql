\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE notebook_owner;
SELECT pg_advisory_xact_lock(887002);
CREATE TABLE IF NOT EXISTS notebook.schema_migrations(version integer PRIMARY KEY);
SELECT NOT EXISTS(SELECT 1 FROM notebook.schema_migrations WHERE version=1) AS apply \gset
\if :apply
  \ir 001-up.sql
  INSERT INTO notebook.schema_migrations(version) VALUES(1);
\endif
COMMIT;
