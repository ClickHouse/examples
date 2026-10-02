\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE usage_owner;
SELECT pg_advisory_xact_lock(831204701);
\ir ../migrations/001_down.sql
DELETE FROM usage.schema_migrations WHERE version = 1;
COMMIT;
