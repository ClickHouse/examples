\set ON_ERROR_STOP on
BEGIN;
CREATE TABLE IF NOT EXISTS nearby_places.schema_migrations (
  version integer PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
SELECT NOT EXISTS (SELECT 1 FROM nearby_places.schema_migrations WHERE version = 1)
  AS apply_migration \gset
\if :apply_migration
CREATE TABLE nearby_places.places (
  id integer PRIMARY KEY,
  name varchar(80) NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 80),
  category text NOT NULL CHECK (category IN ('cafe', 'library', 'park')),
  location public.geography(Point, 4326) NOT NULL
);
CREATE INDEX places_location_gist ON nearby_places.places USING gist (location);
CREATE INDEX places_category ON nearby_places.places (category);
INSERT INTO nearby_places.schema_migrations (version) VALUES (1);
\else
\echo Migration already applied
\endif
GRANT SELECT ON nearby_places.places TO places_reader;
COMMIT;
