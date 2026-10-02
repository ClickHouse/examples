\set ON_ERROR_STOP on
BEGIN;
CREATE TABLE IF NOT EXISTS poll_studio.schema_migrations (
  version integer PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
SELECT NOT EXISTS (SELECT 1 FROM poll_studio.schema_migrations WHERE version = 1)
  AS apply_migration \gset
\if :apply_migration
CREATE TABLE poll_studio.polls (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  question varchar(200) NOT NULL CHECK (
    length(btrim(question)) BETWEEN 1 AND 200 AND question !~ '[[:cntrl:]]'
  ),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  closed_at timestamptz,
  response_count integer NOT NULL DEFAULT 0 CHECK (response_count BETWEEN 0 AND 10000)
);
CREATE INDEX polls_recent ON poll_studio.polls (created_at DESC, id DESC);
CREATE TABLE poll_studio.choices (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  poll_id bigint NOT NULL REFERENCES poll_studio.polls (id),
  position integer NOT NULL CHECK (position BETWEEN 1 AND 8),
  label varchar(80) NOT NULL CHECK (length(btrim(label)) BETWEEN 1 AND 80 AND label !~ '[[:cntrl:]]'),
  UNIQUE (poll_id, position),
  UNIQUE (poll_id, label),
  UNIQUE (poll_id, id)
);
CREATE TABLE poll_studio.responses (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  poll_id bigint NOT NULL REFERENCES poll_studio.polls (id),
  choice_id bigint NOT NULL,
  participant_code varchar(32) NOT NULL CHECK (participant_code ~ '^[A-Z0-9][A-Z0-9_-]{2,31}$'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT response_poll_choice FOREIGN KEY (poll_id, choice_id)
    REFERENCES poll_studio.choices (poll_id, id),
  CONSTRAINT response_poll_code UNIQUE (poll_id, participant_code)
);
CREATE INDEX responses_counts ON poll_studio.responses (poll_id, choice_id);
INSERT INTO poll_studio.schema_migrations (version) VALUES (1);
\else
\echo Migration already applied
\endif
GRANT SELECT, INSERT ON poll_studio.polls, poll_studio.choices, poll_studio.responses TO polls_app;
GRANT UPDATE (response_count, closed_at) ON poll_studio.polls TO polls_app;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA poll_studio TO polls_app;
COMMIT;
