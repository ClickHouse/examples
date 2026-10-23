-- Run as the admin user after `npm run db:migrate`.
\set ON_ERROR_STOP on
BEGIN;

GRANT USAGE ON SCHEMA habit_tracker TO habit_tracker_app;
GRANT SELECT ON habit_tracker.users TO habit_tracker_app;
GRANT SELECT, INSERT ON habit_tracker.habits TO habit_tracker_app;
GRANT UPDATE (archived_at) ON habit_tracker.habits TO habit_tracker_app;
GRANT SELECT, INSERT, DELETE ON habit_tracker.check_ins TO habit_tracker_app;
-- No access to the drizzle schema (migration history) and no DDL.

COMMIT;
