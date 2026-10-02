SET ROLE inspection_owner;
INSERT INTO inspection_api.assets(id, name) VALUES
  (1, 'Synthetic bench <A>'),
  (2, 'Synthetic trolley'),
  (3, 'Synthetic cabinet')
ON CONFLICT (id) DO NOTHING;
INSERT INTO inspection_api.fixture_budget(id, used) VALUES(1, 0)
ON CONFLICT (id) DO NOTHING;
