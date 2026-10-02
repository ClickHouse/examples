-- Administrator only, on a dedicated service. Install pgvector before owner migrations.
\getenv owner_password PG_MIGRATION_PASSWORD
\getenv app_password PG_APP_PASSWORD
CREATE EXTENSION IF NOT EXISTS vector;
CREATE ROLE semantic_owner LOGIN PASSWORD :'owner_password';
CREATE ROLE semantic_app LOGIN PASSWORD :'app_password';
CREATE SCHEMA semantic_notes AUTHORIZATION semantic_owner;
REVOKE ALL ON SCHEMA semantic_notes FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE CREATE, TEMP ON DATABASE postgres FROM PUBLIC;
GRANT CONNECT ON DATABASE postgres TO semantic_owner, semantic_app;
ALTER ROLE semantic_owner SET search_path TO semantic_notes, public;
ALTER ROLE semantic_app SET search_path TO semantic_notes, public;
SELECT extversion AS pgvector_version FROM pg_extension WHERE extname = 'vector';
