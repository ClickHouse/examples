-- Run once as the admin user (postgres). Passwords come from the environment,
-- so they never appear in this file or in shell history.
\set ON_ERROR_STOP on
\getenv migrator_password MIGRATOR_PASSWORD
\getenv app_password APP_PASSWORD

BEGIN;

-- habit_tracker_migrator runs drizzle-kit migrations and owns everything they
-- create: the habit_tracker schema and drizzle-kit's own "drizzle" schema.
CREATE ROLE habit_tracker_migrator LOGIN PASSWORD :'migrator_password';
GRANT CREATE ON DATABASE :"DBNAME" TO habit_tracker_migrator;
-- habit_tracker_app is the runtime role: DML on the app's tables only (sql/02_grants.sql).
CREATE ROLE habit_tracker_app LOGIN PASSWORD :'app_password';

ALTER ROLE habit_tracker_app SET search_path = habit_tracker;
ALTER ROLE habit_tracker_app SET lock_timeout = '2s';
ALTER ROLE habit_tracker_app SET idle_in_transaction_session_timeout = '10s';

COMMIT;
