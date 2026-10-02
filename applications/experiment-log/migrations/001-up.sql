\getenv migration_sha MIGRATION_SHA
BEGIN;
SELECT pg_advisory_xact_lock(hashtextextended('experiment_log:001', 0));
CREATE TABLE IF NOT EXISTS experiment_log.schema_migrations (
  version integer PRIMARY KEY,
  checksum text NOT NULL,
  applied_at timestamptz NOT NULL DEFAULT now()
);
SELECT EXISTS (SELECT 1 FROM experiment_log.schema_migrations WHERE version=1) AS applied \gset
\if :applied
  SELECT checksum = :'migration_sha' AS same FROM experiment_log.schema_migrations WHERE version=1 \gset
  \if :same
    \echo Migration 001 already applied with matching checksum.
  \else
    \echo Migration checksum differs; refusing to continue.
    \quit 3
  \endif
\else
CREATE FUNCTION experiment_log.valid_config(settings jsonb) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE entry record; number numeric;
BEGIN
  IF jsonb_typeof(settings) IS DISTINCT FROM 'object' THEN RETURN false; END IF;
  IF (SELECT count(*) FROM jsonb_object_keys(settings)) > 10 THEN RETURN false; END IF;
  FOR entry IN SELECT key,value FROM jsonb_each(settings) LOOP
    IF entry.key !~ '^[A-Za-z][A-Za-z0-9_]{0,23}$' THEN RETURN false; END IF;
    CASE jsonb_typeof(entry.value)
      WHEN 'string' THEN IF length(entry.value #>> '{}') > 120 THEN RETURN false; END IF;
      WHEN 'boolean' THEN NULL;
      WHEN 'number' THEN
        number := (entry.value #>> '{}')::numeric;
        IF abs(number) > 1000000 OR round(number,6) <> number THEN RETURN false; END IF;
      ELSE RETURN false;
    END CASE;
  END LOOP;
  RETURN true;
END $$;
CREATE FUNCTION experiment_log.valid_measurement_payload(values_json jsonb) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE entry record; value_text text; total integer;
BEGIN
  IF jsonb_typeof(values_json) IS DISTINCT FROM 'object' THEN RETURN false; END IF;
  SELECT count(*) INTO total FROM jsonb_object_keys(values_json);
  IF total NOT BETWEEN 1 AND 10 THEN RETURN false; END IF;
  FOR entry IN SELECT key,value FROM jsonb_each(values_json) LOOP
    IF entry.key !~ '^[a-z][a-z0-9_]{0,31}$' OR jsonb_typeof(entry.value) <> 'string' THEN RETURN false; END IF;
    value_text := entry.value #>> '{}';
    IF length(value_text) > 16 OR value_text !~ '^-?(0|[1-9][0-9]{0,6})(\.[0-9]{1,6})?$' THEN RETURN false; END IF;
    IF abs(value_text::numeric) > 1000000 THEN RETURN false; END IF;
  END LOOP;
  RETURN true;
END $$;
CREATE TABLE experiment_log.projects (
  id uuid PRIMARY KEY,
  name text NOT NULL CHECK (length(name) BETWEEN 1 AND 80)
);
CREATE TABLE experiment_log.runs (
  id uuid PRIMARY KEY,
  project_id uuid NOT NULL REFERENCES experiment_log.projects(id),
  request_id uuid NOT NULL,
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 120),
  config jsonb NOT NULL CHECK (experiment_log.valid_config(config)),
  request_payload jsonb NOT NULL CHECK (
    jsonb_typeof(request_payload) = 'object'
    AND request_payload ?& ARRAY['title','config','measurements']
    AND jsonb_typeof(request_payload->'title') = 'string'
    AND request_payload->>'title' = title AND request_payload->'config' = config
    AND experiment_log.valid_measurement_payload(request_payload->'measurements')
    AND pg_column_size(request_payload) <= 32768
  ),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_xid xid8 NOT NULL DEFAULT pg_current_xact_id(),
  UNIQUE(project_id,request_id),
  UNIQUE(project_id,id)
);
CREATE TABLE experiment_log.measurements (
  project_id uuid NOT NULL,
  run_id uuid NOT NULL,
  name text NOT NULL CHECK (name ~ '^[a-z][a-z0-9_]{0,31}$'),
  -- No typmod rounding: reject excess scale before any precision can be lost.
  value numeric NOT NULL CHECK (abs(value) <= 1000000 AND scale(value) <= 6),
  PRIMARY KEY(project_id,run_id,name),
  FOREIGN KEY(project_id,run_id) REFERENCES experiment_log.runs(project_id,id)
);
CREATE INDEX runs_config_gin ON experiment_log.runs USING gin(config jsonb_path_ops);
CREATE INDEX runs_project_page ON experiment_log.runs(project_id,created_at DESC,id DESC);
CREATE FUNCTION experiment_log.initial_measurement() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE parent_xid xid8; expected text;
BEGIN
  SELECT created_xid,request_payload->'measurements'->>NEW.name INTO parent_xid,expected
    FROM experiment_log.runs WHERE project_id=NEW.project_id AND id=NEW.run_id;
  IF parent_xid IS DISTINCT FROM pg_current_xact_id() THEN
    RAISE EXCEPTION 'Measurements belong only to the initial run transaction' USING ERRCODE='23514';
  END IF;
  IF expected IS NULL OR NEW.value <> expected::numeric THEN
    RAISE EXCEPTION 'Measurement does not match retained payload' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER initial_measurement BEFORE INSERT ON experiment_log.measurements
FOR EACH ROW EXECUTE FUNCTION experiment_log.initial_measurement();
CREATE FUNCTION experiment_log.complete_run() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE actual integer; expected integer;
BEGIN
  SELECT count(*) INTO expected FROM jsonb_object_keys(NEW.request_payload->'measurements');
  SELECT count(*) INTO actual FROM experiment_log.measurements WHERE project_id=NEW.project_id AND run_id=NEW.id;
  IF actual <> expected OR actual NOT BETWEEN 1 AND 10 THEN
    RAISE EXCEPTION 'Run requires its complete measurement set' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;
CREATE CONSTRAINT TRIGGER complete_run AFTER INSERT ON experiment_log.runs
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION experiment_log.complete_run();
INSERT INTO experiment_log.schema_migrations(version,checksum) VALUES(1,:'migration_sha');
\endif
COMMIT;
