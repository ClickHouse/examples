\set ON_ERROR_STOP on
BEGIN;
GRANT SELECT ON asset_audit.items, asset_audit.stocktakes, asset_audit.count_rows TO asset_audit_app;
GRANT UPDATE (counted_quantity) ON asset_audit.count_rows TO asset_audit_app;
GRANT UPDATE (status, revision, finalized_at) ON asset_audit.stocktakes TO asset_audit_app;
COMMIT;
