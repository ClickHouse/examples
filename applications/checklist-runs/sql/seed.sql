\set ON_ERROR_STOP on
INSERT INTO checklist_storage.operators (role_name)
VALUES ('checklist_north'), ('checklist_south') ON CONFLICT DO NOTHING;
INSERT INTO checklist_storage.templates (id, version, title, steps) VALUES
('10000000-0000-4000-8000-000000000001', 1, 'Meeting room opening',
 '["Check lights", "Arrange chairs", "Test display"]'),
('10000000-0000-4000-8000-000000000002', 1, 'Demo station reset',
 '["Clear sample data", "Run smoke check"]'),
('10000000-0000-4000-8000-000000000003', 2, 'Loan desk closing',
 '["Count returned items", "Lock storage", "Leave handover note"]')
ON CONFLICT DO NOTHING;
