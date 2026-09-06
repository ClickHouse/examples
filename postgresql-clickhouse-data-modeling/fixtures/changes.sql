-- Run once after verifying the initial snapshot.
BEGIN;
INSERT INTO users (id, creationdate, displayname, lastaccessdate) VALUES
  (3, '2026-01-03T00:00:00Z', 'New User', '2026-01-03T00:00:00Z');
UPDATE users SET displayname = 'Updated User' WHERE id = 1;
DELETE FROM users WHERE id = 2;
SELECT setval(pg_get_serial_sequence('users', 'id'), 3);
COMMIT;
