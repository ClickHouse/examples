\set ON_ERROR_STOP on
-- Destructive: run explicitly as service administrator after stopping the app.
DROP SCHEMA equipment CASCADE;
DROP ROLE equipment_app;
DROP ROLE equipment_migrator;
