\set ON_ERROR_STOP on
BEGIN;
CREATE TABLE IF NOT EXISTS contact_imports.schema_migrations (
  version integer PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
SELECT NOT EXISTS (SELECT 1 FROM contact_imports.schema_migrations WHERE version = 1)
  AS apply_migration \gset
\if :apply_migration
CREATE TABLE contact_imports.accounts (
  id uuid PRIMARY KEY,
  name text NOT NULL,
  window_start timestamptz NOT NULL DEFAULT clock_timestamp(),
  submission_count integer NOT NULL DEFAULT 0 CHECK (submission_count BETWEEN 0 AND 50)
);
CREATE TABLE contact_imports.imports (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES contact_imports.accounts(id),
  request_id uuid NOT NULL,
  fingerprint char(64) NOT NULL CHECK (fingerprint ~ '^[0-9a-f]{64}$'),
  payload jsonb NOT NULL CHECK (jsonb_typeof(payload) = 'array'),
  row_count integer NOT NULL CHECK (row_count BETWEEN 1 AND 100),
  state text NOT NULL DEFAULT 'queued' CHECK (state IN ('queued', 'succeeded', 'failed')),
  result_count integer,
  error text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  finished_at timestamptz,
  CONSTRAINT imports_request_key UNIQUE (account_id, request_id),
  CONSTRAINT imports_account_key UNIQUE (id, account_id),
  CONSTRAINT payload_count CHECK (jsonb_array_length(payload) = row_count),
  CONSTRAINT terminal_result CHECK (
    (state = 'queued' AND result_count IS NULL AND finished_at IS NULL AND error IS NULL)
    OR (state = 'succeeded' AND result_count IS NOT NULL AND result_count = row_count
      AND finished_at IS NOT NULL AND error IS NULL)
    OR (state = 'failed' AND result_count IS NULL AND finished_at IS NOT NULL AND error IS NOT NULL)
  )
);
CREATE INDEX imports_account_created ON contact_imports.imports (account_id, created_at, id);
CREATE INDEX imports_pending ON contact_imports.imports (account_id) WHERE state = 'queued';
CREATE TABLE contact_imports.contacts (
  import_id uuid NOT NULL,
  account_id uuid NOT NULL,
  row_index integer NOT NULL CHECK (row_index BETWEEN 1 AND 100),
  email varchar(254) NOT NULL,
  name varchar(80) NOT NULL,
  CONSTRAINT contacts_import_key PRIMARY KEY (import_id, email),
  CONSTRAINT contacts_row_key UNIQUE (import_id, row_index),
  CONSTRAINT contacts_account_fk FOREIGN KEY (import_id, account_id)
    REFERENCES contact_imports.imports (id, account_id),
  CHECK (length(email) BETWEEN 3 AND 254 AND length(btrim(name)) BETWEEN 1 AND 80)
);
INSERT INTO contact_imports.schema_migrations (version) VALUES (1);
\else
\echo Application migration already applied
\endif
COMMIT;
