\set ON_ERROR_STOP on
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA equipment TO equipment_app;
REVOKE ALL ON equipment.django_migrations FROM equipment_app;
GRANT SELECT ON equipment.django_migrations TO equipment_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA equipment TO equipment_app;
-- Re-run after every migration that creates tables or sequences.
