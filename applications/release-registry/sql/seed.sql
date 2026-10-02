INSERT INTO registry.projects (id, name) VALUES
('00000000-0000-4000-8000-000000000001','Documentation site'),
('00000000-0000-4000-8000-000000000002','Marketing site')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;
INSERT INTO registry.channels (project_id,name)
SELECT id, channel FROM registry.projects CROSS JOIN (VALUES ('staging'),('production')) AS names(channel)
ON CONFLICT DO NOTHING;
