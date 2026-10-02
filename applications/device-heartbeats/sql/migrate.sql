\set ON_ERROR_STOP on
BEGIN;
SELECT pg_advisory_xact_lock(721149);
CREATE TABLE IF NOT EXISTS heartbeats.schema_versions (
    version integer PRIMARY KEY,
    applied_at timestamptz NOT NULL DEFAULT now()
);
SELECT NOT EXISTS(SELECT FROM heartbeats.schema_versions WHERE version=1) AS apply_v1 \gset
\if :apply_v1
CREATE TABLE heartbeats.projects (
    id text PRIMARY KEY CHECK(id ~ '^[a-z][a-z0-9-]{0,31}$')
);
CREATE TABLE heartbeats.devices (
    project text NOT NULL REFERENCES heartbeats.projects(id),
    id text NOT NULL CHECK(id ~ '^[a-z][a-z0-9-]{0,31}$'),
    latest_sequence bigint NOT NULL DEFAULT 0 CHECK(latest_sequence>=0),
    sample_count integer NOT NULL DEFAULT 0 CHECK(sample_count BETWEEN 0 AND 200),
    PRIMARY KEY(project,id)
);
CREATE TABLE heartbeats.samples (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    project text NOT NULL,
    device text NOT NULL,
    sample_id uuid NOT NULL,
    sequence bigint NOT NULL CHECK(sequence>0),
    reading integer NOT NULL CHECK(reading BETWEEN -1000000 AND 1000000),
    observed_at timestamptz,
    received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT sample_device FOREIGN KEY(project,device) REFERENCES heartbeats.devices(project,id),
    CONSTRAINT retained_sample UNIQUE(project,device,sample_id),
    CONSTRAINT device_sequence UNIQUE(project,device,sequence)
);
CREATE INDEX samples_device_id ON heartbeats.samples(project,device,id DESC);
INSERT INTO heartbeats.schema_versions(version) VALUES(1);
\endif
COMMIT;
