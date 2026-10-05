\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE intake_owner;
GRANT SELECT,INSERT,UPDATE ON intake.batches, intake.staging_rows TO intake_app;
GRANT SELECT,INSERT ON intake.products TO intake_app;
COMMIT;
