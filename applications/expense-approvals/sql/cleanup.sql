\set ON_ERROR_STOP on
-- Only this dedicated example schema and its two roles.
DROP SCHEMA IF EXISTS expenses CASCADE;
DROP ROLE IF EXISTS expense_app;
DROP ROLE IF EXISTS expense_migration;
