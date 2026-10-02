\set ON_ERROR_STOP on
BEGIN;
SELECT pg_advisory_xact_lock(739188);
CREATE TABLE IF NOT EXISTS transfers.schema_versions (
  version integer PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT now()
);
SELECT NOT EXISTS (SELECT FROM transfers.schema_versions WHERE version = 1) AS apply_v1 \gset
\if :apply_v1
CREATE TABLE transfers.organizations (
  id text PRIMARY KEY CHECK (id ~ '^[a-z][a-z0-9-]{0,31}$'),
  label text NOT NULL
);
CREATE TABLE transfers.warehouses (
  organization text NOT NULL REFERENCES transfers.organizations(id),
  id text NOT NULL CHECK (id ~ '^[a-z][a-z0-9-]{0,31}$'),
  label text NOT NULL,
  PRIMARY KEY (organization, id)
);
CREATE TABLE transfers.skus (
  organization text NOT NULL REFERENCES transfers.organizations(id),
  id text NOT NULL CHECK (id ~ '^[a-z][a-z0-9-]{0,31}$'),
  label text NOT NULL,
  PRIMARY KEY (organization, id)
);
CREATE TABLE transfers.balances (
  organization text NOT NULL,
  warehouse text NOT NULL,
  sku text NOT NULL,
  quantity integer NOT NULL CHECK (quantity BETWEEN 0 AND 1000000000),
  PRIMARY KEY (organization, warehouse, sku),
  FOREIGN KEY (organization, warehouse) REFERENCES transfers.warehouses(organization, id),
  FOREIGN KEY (organization, sku) REFERENCES transfers.skus(organization, id)
);
CREATE TABLE transfers.transfers (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  organization text NOT NULL,
  request_id uuid NOT NULL,
  source text NOT NULL,
  destination text NOT NULL,
  sku text NOT NULL,
  units integer NOT NULL CHECK (units BETWEEN 1 AND 1000000),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT different_warehouses CHECK (source <> destination),
  CONSTRAINT organization_request UNIQUE (organization, request_id),
  CONSTRAINT source_balance FOREIGN KEY (organization, source, sku)
    REFERENCES transfers.balances(organization, warehouse, sku),
  CONSTRAINT destination_balance FOREIGN KEY (organization, destination, sku)
    REFERENCES transfers.balances(organization, warehouse, sku)
);
CREATE INDEX transfers_org_id ON transfers.transfers (organization, id DESC);
INSERT INTO transfers.schema_versions (version) VALUES (1);
\endif
COMMIT;
