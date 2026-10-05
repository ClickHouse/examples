-- Credentials come from the environment, not command-line arguments.
\getenv migration_password PG_MIGRATION_PASSWORD
\getenv app_password PG_APP_PASSWORD
\getenv sync_password PG_SYNC_PASSWORD
CREATE ROLE planning_migration LOGIN PASSWORD :'migration_password';
CREATE ROLE planning_app LOGIN PASSWORD :'app_password';
CREATE ROLE planning_sync LOGIN REPLICATION PASSWORD :'sync_password';
GRANT CONNECT ON DATABASE postgres TO planning_migration, planning_app, planning_sync;
GRANT CREATE ON DATABASE postgres TO planning_migration;
