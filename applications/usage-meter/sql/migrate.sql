\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE usage_owner;
SELECT pg_advisory_xact_lock(831204701);
CREATE TABLE IF NOT EXISTS usage.schema_migrations (version INTEGER PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now());
SELECT NOT EXISTS (SELECT FROM usage.schema_migrations WHERE version = 1) AS apply \gset
\if :apply
\ir ../migrations/001_up.sql
INSERT INTO usage.schema_migrations(version) VALUES (1);
\endif
COMMIT;
