-- Owner only; no tokens or scientific results stored in this seed.
INSERT INTO experiment_log.projects(id,name) VALUES
('00000000-0000-4000-8000-000000000001','Synthetic Alpha'),
('00000000-0000-4000-8000-000000000002','Synthetic Beta')
ON CONFLICT(id) DO NOTHING;
