-- Preserve administrator-created schemas. The migration owner deliberately
-- lacks CREATE on the database and can still undo all application objects.
DROP FUNCTION checklist_api.start_run(uuid, uuid, text);
DROP FUNCTION checklist_api.complete_step(uuid, bigint, integer, text);
DROP FUNCTION checklist_api.list_runs(bigint, integer);
DROP FUNCTION checklist_api.run_steps(checklist_api.runs);
DROP FUNCTION checklist_api.completions(checklist_api.runs);
DROP VIEW checklist_api.completions, checklist_api.run_steps, checklist_api.runs, checklist_api.templates;
DROP FUNCTION checklist_storage.check_request();
DROP TABLE checklist_storage.completions, checklist_storage.run_steps,
    checklist_storage.runs, checklist_storage.templates, checklist_storage.operators,
    checklist_storage.schema_migrations;
NOTIFY pgrst, 'reload schema';
