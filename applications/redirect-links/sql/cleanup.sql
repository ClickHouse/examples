\set ON_ERROR_STOP on
DROP SCHEMA IF EXISTS redirect_links CASCADE;
SELECT format('DROP OWNED BY %I',rolname) FROM pg_roles
WHERE rolname IN ('redirects_app','redirects_migration') \gexec
DROP ROLE IF EXISTS redirects_app;
DROP ROLE IF EXISTS redirects_migration;
-- Dedicated fixture reset; PUBLIC revocations remain. Not a production downgrade.
