-- DESTRUCTIVE: run as the service administrator to remove this example only.
-- This permanently deletes every request, vote and Prisma migration record.
\set ON_ERROR_STOP on
BEGIN;
DROP SCHEMA IF EXISTS feature_board CASCADE;
REVOKE CONNECT ON DATABASE :"DBNAME" FROM feature_board_app, feature_board_migration;
DROP ROLE IF EXISTS feature_board_app;
DROP ROLE IF EXISTS feature_board_migration;

COMMIT;
