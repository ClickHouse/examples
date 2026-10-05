BEGIN;
CREATE SCHEMA planning;
CREATE TABLE planning.projects (
  id uuid PRIMARY KEY, board_id text NOT NULL, name text NOT NULL,
  color text NOT NULL CHECK (color ~ '^#[0-9A-Fa-f]{6}$'),
  UNIQUE(id, board_id)
);
CREATE TABLE planning.tasks (
  id uuid PRIMARY KEY, board_id text NOT NULL, project_id uuid NOT NULL,
  title text NOT NULL CHECK (length(trim(title)) BETWEEN 1 AND 120),
  status text NOT NULL CHECK (status IN ('todo','doing','done')),
  priority text NOT NULL CHECK (priority IN ('low','medium','high')),
  revision integer NOT NULL DEFAULT 1 CHECK (revision > 0),
  FOREIGN KEY(project_id,board_id) REFERENCES planning.projects(id,board_id)
);
CREATE INDEX tasks_board ON planning.tasks(board_id);
CREATE INDEX projects_board ON planning.projects(board_id);
ALTER TABLE planning.tasks REPLICA IDENTITY FULL;
ALTER TABLE planning.projects REPLICA IDENTITY FULL;
GRANT USAGE ON SCHEMA planning TO planning_app, planning_sync;
GRANT SELECT ON planning.projects TO planning_app;
GRANT SELECT, INSERT, UPDATE ON planning.tasks TO planning_app;
GRANT SELECT ON planning.projects, planning.tasks TO planning_sync;
COMMIT;
