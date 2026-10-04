\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE topology_owner;
INSERT INTO service_topology.graphs (id, title, revision, document) VALUES
('67bc2cf0-5b0f-45c8-bf6a-7b4bb5155a50', 'Storefront architecture', 1, '{
  "nodes": [
    {"id":"11111111-1111-4111-8111-111111111111","type":"service","position":{"x":80,"y":100},"data":{"label":"Storefront","kind":"web"}},
    {"id":"22222222-2222-4222-8222-222222222222","type":"service","position":{"x":350,"y":100},"data":{"label":"Checkout API","kind":"api"}},
    {"id":"33333333-3333-4333-8333-333333333333","type":"service","position":{"x":620,"y":20},"data":{"label":"Orders Postgres","kind":"database"}},
    {"id":"44444444-4444-4444-8444-444444444444","type":"service","position":{"x":620,"y":180},"data":{"label":"Fulfilment worker","kind":"worker"}},
    {"id":"55555555-5555-4555-8555-555555555555","type":"service","position":{"x":890,"y":180},"data":{"label":"Warehouse API","kind":"api"}}
  ],
  "edges": [
    {"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","source":"11111111-1111-4111-8111-111111111111","target":"22222222-2222-4222-8222-222222222222"},
    {"id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","source":"22222222-2222-4222-8222-222222222222","target":"33333333-3333-4333-8333-333333333333"},
    {"id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","source":"22222222-2222-4222-8222-222222222222","target":"44444444-4444-4444-8444-444444444444"},
    {"id":"dddddddd-dddd-4ddd-8ddd-dddddddddddd","source":"44444444-4444-4444-8444-444444444444","target":"55555555-5555-4555-8555-555555555555"}
  ]
}'::jsonb) ON CONFLICT (id) DO NOTHING;
INSERT INTO service_topology.revisions (graph_id, revision, document)
SELECT id, revision, document FROM service_topology.graphs
WHERE id = '67bc2cf0-5b0f-45c8-bf6a-7b4bb5155a50'
ON CONFLICT DO NOTHING;
COMMIT;
