-- Schema owner only, after migration.
GRANT USAGE ON SCHEMA semantic_notes TO semantic_app;
GRANT SELECT ON semantic_notes.collection, semantic_notes.notes TO semantic_app;
-- FOR UPDATE needs UPDATE privilege; the singleton id is fixed to 1 by CHECK.
GRANT UPDATE (id) ON semantic_notes.collection TO semantic_app;
GRANT INSERT ON semantic_notes.notes TO semantic_app;
GRANT UPDATE (title, body, embedding, revision, updated_at) ON semantic_notes.notes TO semantic_app;
