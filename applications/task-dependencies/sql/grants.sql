\set ON_ERROR_STOP on
REVOKE ALL ON SCHEMA task_dependencies FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA task_dependencies FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA task_dependencies FROM PUBLIC;
GRANT USAGE ON SCHEMA task_dependencies TO tasks_runtime;
GRANT SELECT ON task_dependencies.projects,task_dependencies.tasks,task_dependencies.edges,task_dependencies.schema_migrations TO tasks_runtime;
GRANT UPDATE(revision) ON task_dependencies.projects TO tasks_runtime;
GRANT INSERT ON task_dependencies.tasks,task_dependencies.edges TO tasks_runtime;
GRANT UPDATE(done,done_at) ON task_dependencies.tasks TO tasks_runtime;
GRANT DELETE ON task_dependencies.edges TO tasks_runtime;
GRANT EXECUTE ON FUNCTION task_dependencies.enforce_bounds() TO tasks_runtime;
