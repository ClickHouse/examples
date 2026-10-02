\set ON_ERROR_STOP on
GRANT SELECT, INSERT, UPDATE ON invoice_tracker.users, invoice_tracker.invoices TO invoice_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON invoice_tracker.invoice_lines, invoice_tracker.sessions TO invoice_app;
GRANT SELECT ON invoice_tracker.migrations TO invoice_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA invoice_tracker TO invoice_app;
