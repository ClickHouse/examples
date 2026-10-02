\set ON_ERROR_STOP on
-- Destructive: run explicitly as service administrator after stopping the app.
DROP SCHEMA support_desk CASCADE;
DROP ROLE support_desk_app;
DROP ROLE support_desk_migrator;
