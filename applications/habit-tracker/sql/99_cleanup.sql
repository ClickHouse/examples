-- DESTRUCTIVE: run as the admin user to remove this example's schemas and roles.
\set ON_ERROR_STOP on
BEGIN;
-- habit_tracker holds the app's tables; drizzle holds drizzle-kit's migration history.
DROP SCHEMA IF EXISTS habit_tracker, drizzle CASCADE;
-- Removes anything else the roles own and revokes their privileges, such as CREATE on the database.
DROP OWNED BY habit_tracker_app, habit_tracker_migrator;
DROP ROLE habit_tracker_app;
DROP ROLE habit_tracker_migrator;
COMMIT;
