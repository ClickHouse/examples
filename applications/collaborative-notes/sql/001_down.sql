BEGIN;
SELECT pg_advisory_xact_lock(1002, 31);
DROP TABLE notes.documents;
COMMIT;
