\set ON_ERROR_STOP on
GRANT USAGE ON SCHEMA checklist_api, checklist_storage TO checklist_north, checklist_south;
GRANT SELECT ON ALL TABLES IN SCHEMA checklist_storage TO checklist_north, checklist_south;
GRANT SELECT ON ALL TABLES IN SCHEMA checklist_api TO checklist_north, checklist_south;
GRANT UPDATE (lock_nonce) ON checklist_storage.operators TO checklist_north, checklist_south;
GRANT INSERT ON checklist_storage.runs, checklist_storage.run_steps, checklist_storage.completions
    TO checklist_north, checklist_south;
GRANT UPDATE (start_result, completed_steps, completed_at) ON checklist_storage.runs
    TO checklist_north, checklist_south;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA checklist_storage TO checklist_north, checklist_south;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA checklist_api TO checklist_north, checklist_south;
GRANT EXECUTE ON FUNCTION checklist_storage.check_request() TO checklist_north, checklist_south;
-- Only the impersonated roles need API/storage access. The authenticator has no
-- owner membership and does not inherit these grants without SET ROLE.
NOTIFY pgrst, 'reload schema';
