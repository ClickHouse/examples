-- Run as the migration role after `npm run db:migrate`.
\set ON_ERROR_STOP on
BEGIN;

-- The app can read requests, create them, edit content/status and delete them.
-- Ownership is checked in src/lib/board.ts on every authenticated mutation.
GRANT SELECT, INSERT, DELETE ON feature_board.feature_requests TO feature_board_app;
GRANT UPDATE (title, description, status, updated_at)
  ON feature_board.feature_requests TO feature_board_app;
GRANT SELECT, INSERT, DELETE ON feature_board.votes TO feature_board_app;
-- No grants on Prisma's migration history, schema creation or role management.

COMMIT;
