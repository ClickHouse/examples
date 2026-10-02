\set ON_ERROR_STOP on
GRANT SELECT, INSERT, UPDATE ON support_desk.users, support_desk.tickets TO support_desk_app;
GRANT SELECT, INSERT ON support_desk.replies TO support_desk_app;
GRANT SELECT ON support_desk.schema_migrations, support_desk.ar_internal_metadata TO support_desk_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA support_desk TO support_desk_app;
-- Runtime replies are append-only; reapply after migrations add objects.
