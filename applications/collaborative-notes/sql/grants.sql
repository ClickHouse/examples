-- Run as notes_owner after migration and seed.
REVOKE ALL ON SCHEMA notes FROM PUBLIC;
GRANT USAGE ON SCHEMA notes TO notes_runtime;
REVOKE ALL ON notes.documents FROM PUBLIC, notes_runtime;
GRANT SELECT ON notes.documents TO notes_runtime;
GRANT UPDATE (state, revision, stored_at) ON notes.documents TO notes_runtime;
