CREATE TABLE task_dependencies.projects (
 id uuid PRIMARY KEY,
 account_id uuid NOT NULL,
 name text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 100),
 revision bigint NOT NULL DEFAULT 0 CHECK (revision BETWEEN 0 AND 1000000000),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX projects_account_cursor ON task_dependencies.projects(account_id,id);
CREATE TABLE task_dependencies.tasks (
 id uuid PRIMARY KEY,
 project_id uuid NOT NULL REFERENCES task_dependencies.projects(id),
 title text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 100),
 done boolean NOT NULL DEFAULT false,
 done_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(project_id,id),
 CHECK ((done AND done_at IS NOT NULL) OR (NOT done AND done_at IS NULL))
);
CREATE TABLE task_dependencies.edges (
 project_id uuid NOT NULL REFERENCES task_dependencies.projects(id),
 task_id uuid NOT NULL,
 prerequisite_id uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(project_id,task_id,prerequisite_id),
 FOREIGN KEY(project_id,task_id) REFERENCES task_dependencies.tasks(project_id,id),
 FOREIGN KEY(project_id,prerequisite_id) REFERENCES task_dependencies.tasks(project_id,id),
 CHECK (task_id <> prerequisite_id)
);
CREATE FUNCTION task_dependencies.enforce_bounds() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE count_now integer;
BEGIN
 PERFORM 1 FROM task_dependencies.projects WHERE id=NEW.project_id FOR UPDATE;
 IF TG_TABLE_NAME='tasks' THEN
  SELECT count(*) INTO count_now FROM task_dependencies.tasks WHERE project_id=NEW.project_id;
  IF count_now>=100 THEN RAISE EXCEPTION 'task limit' USING ERRCODE='23514'; END IF;
 ELSE
  SELECT count(*) INTO count_now FROM task_dependencies.edges WHERE project_id=NEW.project_id;
  IF count_now>=300 THEN RAISE EXCEPTION 'edge limit' USING ERRCODE='23514'; END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER task_bound BEFORE INSERT ON task_dependencies.tasks FOR EACH ROW EXECUTE FUNCTION task_dependencies.enforce_bounds();
CREATE TRIGGER edge_bound BEFORE INSERT ON task_dependencies.edges FOR EACH ROW EXECUTE FUNCTION task_dependencies.enforce_bounds();
