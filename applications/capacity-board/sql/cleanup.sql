\set ON_ERROR_STOP on
DROP SCHEMA IF EXISTS capacity_board CASCADE;
DROP OWNED BY capacity_app, capacity_migration;
DROP ROLE capacity_app;
DROP ROLE capacity_migration;
