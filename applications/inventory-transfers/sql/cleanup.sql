\set ON_ERROR_STOP on
DROP SCHEMA IF EXISTS transfers CASCADE;
SELECT format('DROP OWNED BY %I', rolname) FROM pg_roles
WHERE rolname IN ('transfers_app', 'transfers_migration') \gexec
DROP ROLE IF EXISTS transfers_app;
DROP ROLE IF EXISTS transfers_migration;
-- Dedicated-fixture reset only; PUBLIC privilege revocations remain in place.
