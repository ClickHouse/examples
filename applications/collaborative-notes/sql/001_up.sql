BEGIN;
SELECT pg_advisory_xact_lock(1002, 31);
CREATE TABLE notes.documents (
  id text PRIMARY KEY CHECK (id IN ('release-planning', 'meeting-notes', 'workshop-checklist')),
  title text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 80),
  state bytea NOT NULL CHECK (octet_length(state) BETWEEN 2 AND 524288),
  revision integer NOT NULL DEFAULT 0 CHECK (revision BETWEEN 0 AND 1000000000),
  stored_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
COMMIT;
