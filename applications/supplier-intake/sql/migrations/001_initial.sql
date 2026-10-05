\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE intake_owner;
CREATE TABLE intake.batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), fingerprint text NOT NULL UNIQUE CHECK (fingerprint ~ '^[a-f0-9]{64}$'),
  filename text NOT NULL CHECK (length(filename) BETWEEN 1 AND 120), format text NOT NULL CHECK (format IN ('csv','xlsx')),
  headers jsonb NOT NULL CHECK (jsonb_typeof(headers)='array'), row_count integer NOT NULL CHECK (row_count BETWEEN 1 AND 100),
  supplier text NOT NULL DEFAULT '', mapping jsonb, revision integer NOT NULL DEFAULT 1 CHECK (revision>0),
  status text NOT NULL DEFAULT 'uploaded' CHECK (status IN ('uploaded','reviewed','promoted')),
  invalid_count integer NOT NULL DEFAULT 0 CHECK (invalid_count BETWEEN 0 AND 100), created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE intake.staging_rows (
  batch_id uuid NOT NULL REFERENCES intake.batches(id), row_number integer NOT NULL CHECK (row_number BETWEEN 2 AND 101),
  raw_values jsonb NOT NULL, mapped_values jsonb, errors jsonb NOT NULL DEFAULT '[]',
  PRIMARY KEY (batch_id,row_number), CHECK (jsonb_typeof(errors)='array')
);
CREATE TABLE intake.products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), batch_id uuid NOT NULL, row_number integer NOT NULL,
  supplier text NOT NULL CHECK (length(supplier) BETWEEN 2 AND 80), supplier_key text NOT NULL,
  sku text NOT NULL CHECK (sku ~ '^[A-Z0-9_-]{1,32}$'), product text NOT NULL CHECK (length(product) BETWEEN 1 AND 120),
  price_cents integer NOT NULL CHECK (price_cents BETWEEN 1 AND 99999999), stock integer NOT NULL CHECK (stock BETWEEN 0 AND 1000000),
  FOREIGN KEY (batch_id,row_number) REFERENCES intake.staging_rows(batch_id,row_number),
  UNIQUE (supplier_key,sku), UNIQUE (batch_id,row_number), CHECK (supplier_key=lower(supplier))
);
CREATE INDEX batches_recent ON intake.batches(created_at DESC);
COMMIT;
