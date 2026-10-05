BEGIN;
CREATE SCHEMA tracker;
CREATE SCHEMA tracker_private;
CREATE TABLE tracker.workspaces(id uuid PRIMARY KEY,name text NOT NULL);
CREATE TABLE tracker.projects(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 workspace_id uuid NOT NULL DEFAULT nullif(current_setting('app.workspace_id',true),'')::uuid REFERENCES tracker.workspaces(id),
 name text NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 80),
 created_at timestamptz NOT NULL DEFAULT now(),
 description text NOT NULL DEFAULT '' CHECK(length(description)<=500),
 UNIQUE(id,workspace_id)
);
CREATE TABLE tracker.tasks(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 workspace_id uuid NOT NULL DEFAULT nullif(current_setting('app.workspace_id',true),'')::uuid,
 project_id uuid NOT NULL,
 title text NOT NULL CHECK(length(trim(title)) BETWEEN 1 AND 120),
 done boolean NOT NULL DEFAULT false,
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(project_id,workspace_id) REFERENCES tracker.projects(id,workspace_id)
);
CREATE INDEX projects_recent ON tracker.projects(created_at,id);
CREATE INDEX tasks_recent ON tracker.tasks(created_at,id);
CREATE INDEX projects_workspace ON tracker.projects(workspace_id);
CREATE INDEX tasks_project ON tracker.tasks(project_id,workspace_id);
ALTER TABLE tracker.workspaces ENABLE ROW LEVEL SECURITY;
ALTER TABLE tracker.projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE tracker.tasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY workspace_access ON tracker.workspaces TO tracker_member USING(id=nullif(current_setting('app.workspace_id',true),'')::uuid);
CREATE POLICY project_access ON tracker.projects TO tracker_member USING(workspace_id=nullif(current_setting('app.workspace_id',true),'')::uuid) WITH CHECK(workspace_id=nullif(current_setting('app.workspace_id',true),'')::uuid);
CREATE POLICY task_access ON tracker.tasks TO tracker_member USING(workspace_id=nullif(current_setting('app.workspace_id',true),'')::uuid) WITH CHECK(workspace_id=nullif(current_setting('app.workspace_id',true),'')::uuid);
CREATE TABLE tracker_private.accounts(id uuid PRIMARY KEY,email text UNIQUE NOT NULL,workspace_id uuid NOT NULL REFERENCES tracker.workspaces(id),workspace_name text NOT NULL,salt text NOT NULL,password_hash text NOT NULL);
CREATE TABLE tracker_private.sessions(token_hash text PRIMARY KEY,account_id uuid NOT NULL REFERENCES tracker_private.accounts(id),expires_at timestamptz NOT NULL);
GRANT USAGE ON SCHEMA tracker TO tracker_member;
GRANT SELECT ON tracker.workspaces TO tracker_member;
GRANT SELECT,INSERT,UPDATE ON tracker.projects,tracker.tasks TO tracker_member;
GRANT USAGE ON SCHEMA tracker_private TO tracker_api;
GRANT SELECT ON tracker_private.accounts TO tracker_api;
GRANT SELECT,INSERT,DELETE ON tracker_private.sessions TO tracker_api;
COMMIT;
