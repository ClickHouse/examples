INSERT INTO webhook.integrations (id, name) VALUES
('00000000-0000-4000-8000-000000000001', 'Documentation site'),
('00000000-0000-4000-8000-000000000002', 'Marketing site')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;
INSERT INTO webhook.counters (integration_id)
SELECT id FROM webhook.integrations ON CONFLICT DO NOTHING;
