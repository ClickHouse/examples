CREATE TABLE registry.projects (id UUID PRIMARY KEY, name TEXT NOT NULL UNIQUE);
CREATE TABLE registry.releases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES registry.projects(id),
  version TEXT NOT NULL CHECK (length(version) BETWEEN 1 AND 64),
  digest TEXT NOT NULL CHECK (digest ~ '^sha256:[0-9a-f]{64}$'),
  metadata JSONB NOT NULL CHECK (jsonb_typeof(metadata) = 'object' AND octet_length(metadata::text) <= 4096),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (project_id, version), UNIQUE (project_id, id)
);
CREATE TABLE registry.channels (
  project_id UUID NOT NULL REFERENCES registry.projects(id),
  name TEXT NOT NULL CHECK (name IN ('staging', 'production')),
  release_id UUID,
  revision BIGINT NOT NULL DEFAULT 0 CHECK (revision >= 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (project_id, name),
  FOREIGN KEY (project_id, release_id) REFERENCES registry.releases(project_id, id)
);
CREATE INDEX releases_project_created ON registry.releases (project_id, created_at DESC, id DESC);
GRANT SELECT ON registry.projects, registry.releases, registry.channels TO registry_app;
GRANT INSERT (project_id, version, digest, metadata) ON registry.releases TO registry_app;
GRANT UPDATE (release_id, revision, updated_at) ON registry.channels TO registry_app;
