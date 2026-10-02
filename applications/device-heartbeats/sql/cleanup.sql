\set ON_ERROR_STOP on
DROP SCHEMA IF EXISTS heartbeats CASCADE;
SELECT format('DROP OWNED BY %I',rolname) FROM pg_roles
WHERE rolname IN('heartbeats_app','heartbeats_migration') \gexec
DROP ROLE IF EXISTS heartbeats_app;
DROP ROLE IF EXISTS heartbeats_migration;
-- Dedicated fixture reset; PUBLIC revocations remain. Not a production downgrade.
