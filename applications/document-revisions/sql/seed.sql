SET ROLE revision_owner;
INSERT INTO revision_api.accounts(id, name) VALUES
    ('00000000-0000-0000-0000-000000000001', 'Editorial team'),
    ('00000000-0000-0000-0000-000000000002', 'Support team')
ON CONFLICT (id) DO NOTHING;
