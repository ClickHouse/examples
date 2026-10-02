\set ON_ERROR_STOP on
-- Administrator-only reset for this dedicated fixture, after the app stops.
DROP SCHEMA IF EXISTS nearby_places CASCADE;
DROP ROLE IF EXISTS places_reader;
DROP ROLE IF EXISTS places_migration;
-- Keep the administrator-owned PostGIS extension for bootstrap repetition.
