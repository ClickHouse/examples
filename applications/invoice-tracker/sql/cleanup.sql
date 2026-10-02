\set ON_ERROR_STOP on
-- Destructive: dedicated app only, administrator, server stopped.
DROP SCHEMA invoice_tracker CASCADE;
DROP ROLE invoice_app;
DROP ROLE invoice_migrator;
