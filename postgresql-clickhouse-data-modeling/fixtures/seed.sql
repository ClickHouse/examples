-- Tiny synthetic Stack Overflow-shaped fixture, not the public dataset.
BEGIN;
INSERT INTO users (id, creationdate, displayname, lastaccessdate) VALUES
  (1, '2026-01-01T00:00:00Z', 'Alice Example', '2026-01-01T00:00:00Z'),
  (2, '2026-01-02T00:00:00Z', 'Bob Example', '2026-01-02T00:00:00Z');
INSERT INTO posts (id, posttypeid, creationdate, owneruserid, title, score) VALUES
  (1, 1, '2026-01-01T00:00:00Z', 1, 'How does CDC work?', 10),
  (2, 1, '2026-01-02T00:00:00Z', 2, 'What does FINAL do?', 20);
INSERT INTO votes (id, postid, votetypeid, creationdate, userid) VALUES
  (1, 1, 2, '2026-01-02T00:00:00Z', 2);
INSERT INTO comments (id, postid, text, creationdate, userid) VALUES
  (1, 1, 'A tiny deterministic example', '2026-01-02T00:00:00Z', 2);
SELECT setval(pg_get_serial_sequence('users', 'id'), 2);
SELECT setval(pg_get_serial_sequence('posts', 'id'), 2);
SELECT setval(pg_get_serial_sequence('votes', 'id'), 1);
SELECT setval(pg_get_serial_sequence('comments', 'id'), 1);
COMMIT;
