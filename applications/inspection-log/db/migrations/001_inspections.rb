# frozen_string_literal: true
Sequel.migration do
  up do
    run <<~SQL
      CREATE TABLE inspection_api.assets (
        id integer PRIMARY KEY CHECK (id BETWEEN 1 AND 3),
        name text NOT NULL CHECK (length(name) BETWEEN 1 AND 120)
      );
      CREATE TABLE inspection_api.fixture_budget (
        id integer PRIMARY KEY CHECK (id = 1),
        used integer NOT NULL CHECK (used BETWEEN 0 AND 200)
      );
      CREATE TABLE inspection_api.inspections (
        id integer PRIMARY KEY CHECK (id BETWEEN 1 AND 200),
        request_id uuid NOT NULL UNIQUE,
        digest text NOT NULL CHECK (digest ~ '^[0-9a-f]{64}$'),
        asset_id integer NOT NULL REFERENCES inspection_api.assets(id),
        inspected_on date NOT NULL CHECK (inspected_on BETWEEN DATE '2000-01-01' AND DATE '2100-12-31'),
        outcome text NOT NULL CHECK (outcome IN ('pass', 'watch', 'fail')),
        note text NOT NULL CHECK (length(note) <= 600),
        created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
      CREATE TABLE inspection_api.inspection_results (
        inspection_id integer NOT NULL REFERENCES inspection_api.inspections(id),
        check_name text NOT NULL CHECK (check_name IN ('housing', 'cable', 'label')),
        result text NOT NULL CHECK (result IN ('ok', 'issue')),
        PRIMARY KEY (inspection_id, check_name)
      );
      CREATE INDEX inspection_history ON inspection_api.inspections(asset_id, inspected_on DESC, id DESC);
      GRANT SELECT ON inspection_api.assets, inspection_api.fixture_budget,
        inspection_api.inspections, inspection_api.inspection_results TO inspection_app;
      GRANT INSERT ON inspection_api.inspections, inspection_api.inspection_results TO inspection_app;
      GRANT UPDATE (used) ON inspection_api.fixture_budget TO inspection_app;
    SQL
  end

  down do
    drop_table Sequel.qualify(:inspection_api, :inspection_results)
    drop_table Sequel.qualify(:inspection_api, :inspections)
    drop_table Sequel.qualify(:inspection_api, :fixture_budget)
    drop_table Sequel.qualify(:inspection_api, :assets)
  end
end
