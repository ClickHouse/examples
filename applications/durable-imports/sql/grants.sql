\set ON_ERROR_STOP on
-- Run after application/queue migrations and owner-only queue creation.
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA import_jobs FROM PUBLIC;
GRANT SELECT ON contact_imports.accounts, contact_imports.imports, contact_imports.contacts
  TO imports_api, imports_worker;
-- FOR UPDATE for quota coordination also needs UPDATE on an account column.
GRANT UPDATE (window_start, submission_count) ON contact_imports.accounts TO imports_api;
GRANT INSERT ON contact_imports.imports TO imports_api;
GRANT UPDATE (state, error, finished_at) ON contact_imports.imports TO imports_api;
GRANT INSERT ON contact_imports.contacts TO imports_worker;
GRANT UPDATE (state, error, finished_at, result_count) ON contact_imports.imports TO imports_worker;

GRANT SELECT ON import_jobs.version, import_jobs.queue, import_jobs.job, import_jobs.job_common
  TO imports_api, imports_worker;
GRANT INSERT ON import_jobs.job_common TO imports_api;
-- The worker must claim/settle jobs and run ordinary expiry/retention supervision.
GRANT INSERT, UPDATE, DELETE ON import_jobs.job, import_jobs.job_common TO imports_worker;
GRANT UPDATE ON import_jobs.queue TO imports_worker;
-- Supervisor cadence gates, not the schema version or index-rebuild gate.
GRANT UPDATE (flow_on, monitor_backoff_on) ON import_jobs.version TO imports_worker;
GRANT SELECT, UPDATE, DELETE ON import_jobs.job_dependency TO imports_worker;
GRANT EXECUTE ON FUNCTION import_jobs.job_now() TO imports_api, imports_worker;
-- No schema CREATE, queue creation/helper EXECUTE, TRUNCATE or index ownership.
-- Scheduling, persistent stats partitions and runtime index rebuilding are disabled.
