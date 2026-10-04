\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE harvest_owner;
GRANT SELECT ON harvest.crops, harvest.beds TO harvest_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON harvest.entries TO harvest_app;
COMMIT;
