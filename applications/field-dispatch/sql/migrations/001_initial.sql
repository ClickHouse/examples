\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE dispatch_owner;
CREATE TABLE dispatch.areas (
  id uuid PRIMARY KEY,
  name text NOT NULL CHECK (length(name) BETWEEN 1 AND 80),
  color text NOT NULL CHECK (color ~ '^#[0-9a-fA-F]{6}$'),
  boundary public.geometry(Polygon, 4326) NOT NULL,
  CHECK (public.ST_IsValid(boundary) AND NOT public.ST_IsEmpty(boundary))
);
CREATE INDEX areas_boundary_gist ON dispatch.areas USING gist (boundary);
CREATE TABLE dispatch.teams (
  id uuid PRIMARY KEY,
  name text NOT NULL,
  area_id uuid NOT NULL REFERENCES dispatch.areas(id),
  depot public.geometry(Point, 4326) NOT NULL
);
CREATE TABLE dispatch.jobs (
  id uuid PRIMARY KEY,
  code text NOT NULL UNIQUE,
  title text NOT NULL,
  priority text NOT NULL CHECK (priority IN ('routine', 'urgent')),
  geom public.geometry(Point, 4326) NOT NULL,
  team_id uuid REFERENCES dispatch.teams(id),
  revision integer NOT NULL DEFAULT 1 CHECK (revision > 0)
);
CREATE INDEX jobs_geom_gist ON dispatch.jobs USING gist (geom);
CREATE TABLE dispatch.map_state (
  id text PRIMARY KEY CHECK (id = 'dispatch'),
  longitude double precision NOT NULL CHECK (longitude BETWEEN -1.52 AND -1.40),
  latitude double precision NOT NULL CHECK (latitude BETWEEN 53.32 AND 53.42),
  zoom double precision NOT NULL CHECK (zoom BETWEEN 12 AND 16),
  area_id uuid NOT NULL REFERENCES dispatch.areas(id),
  mode text NOT NULL CHECK (mode IN ('assignments', 'priority')),
  revision integer NOT NULL DEFAULT 1 CHECK (revision > 0)
);
COMMIT;
