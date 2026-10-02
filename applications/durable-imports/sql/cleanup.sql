\set ON_ERROR_STOP on
-- Destructive, dedicated-fixture cleanup by the administrator after processes stop.
DROP SCHEMA IF EXISTS contact_imports CASCADE;
DROP SCHEMA IF EXISTS import_jobs CASCADE;
DROP ROLE IF EXISTS imports_api;
DROP ROLE IF EXISTS imports_worker;
DROP ROLE IF EXISTS imports_migration;
