\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE harvest_owner;
CREATE TABLE harvest.crops (
  id uuid PRIMARY KEY, name text NOT NULL UNIQUE CHECK (length(name) BETWEEN 1 AND 60)
);
CREATE TABLE harvest.beds (
  id uuid PRIMARY KEY, name text NOT NULL UNIQUE CHECK (length(name) BETWEEN 1 AND 60)
);
CREATE TABLE harvest.entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  crop_id uuid NOT NULL REFERENCES harvest.crops(id),
  bed_id uuid NOT NULL REFERENCES harvest.beds(id),
  harvested_on date NOT NULL CHECK (harvested_on BETWEEN DATE '1900-01-01' AND DATE '2100-12-31'),
  grams integer NOT NULL CHECK (grams BETWEEN 1 AND 1000000),
  note text NOT NULL DEFAULT '' CHECK (length(note) <= 500),
  version integer NOT NULL DEFAULT 1 CHECK (version BETWEEN 1 AND 2000000000)
);
CREATE INDEX harvest_entries_date ON harvest.entries (harvested_on DESC);
CREATE INDEX harvest_entries_crop_date ON harvest.entries (crop_id, harvested_on DESC);
COMMIT;
