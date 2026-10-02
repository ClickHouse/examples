CREATE TABLE notebook.customers (
  id uuid PRIMARY KEY,
  name text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 100),
  note text NOT NULL DEFAULT '' CHECK (char_length(note) <= 2000),
  health text NOT NULL DEFAULT 'healthy' CHECK (health IN ('healthy','watch','risk')),
  revision bigint NOT NULL DEFAULT 0 CHECK (revision BETWEEN 0 AND 999999999999999999),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE notebook.customer_edits (
  customer_id uuid NOT NULL REFERENCES notebook.customers(id),
  revision bigint NOT NULL CHECK (revision BETWEEN 1 AND 999999999999999999),
  note text NOT NULL CHECK (char_length(note) <= 2000),
  health text NOT NULL CHECK (health IN ('healthy','watch','risk')),
  edited_at timestamptz NOT NULL,
  PRIMARY KEY (customer_id,revision)
);
GRANT SELECT ON notebook.customers,notebook.customer_edits TO notebook_app;
GRANT UPDATE(note,health,revision,updated_at) ON notebook.customers TO notebook_app;
GRANT INSERT ON notebook.customer_edits TO notebook_app;
