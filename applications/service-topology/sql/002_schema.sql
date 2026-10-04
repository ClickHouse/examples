\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE topology_owner;
CREATE TABLE service_topology.graphs (
  id UUID PRIMARY KEY,
  title TEXT NOT NULL CHECK (length(title) BETWEEN 1 AND 80),
  revision INTEGER NOT NULL CHECK (revision > 0),
  document JSONB NOT NULL CHECK (
    document ? 'nodes' AND document ? 'edges' AND
    jsonb_typeof(document) = 'object' AND
    jsonb_typeof(document->'nodes') = 'array' AND
    jsonb_typeof(document->'edges') = 'array' AND
    jsonb_array_length(document->'nodes') <= 100 AND
    jsonb_array_length(document->'edges') <= 200
  ),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE service_topology.revisions (
  graph_id UUID NOT NULL REFERENCES service_topology.graphs(id) ON DELETE CASCADE,
  revision INTEGER NOT NULL CHECK (revision > 0),
  document JSONB NOT NULL,
  saved_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (graph_id, revision)
);
GRANT SELECT ON service_topology.graphs, service_topology.revisions TO topology_app;
GRANT UPDATE (revision, document, updated_at) ON service_topology.graphs TO topology_app;
GRANT INSERT ON service_topology.revisions TO topology_app;
COMMIT;
