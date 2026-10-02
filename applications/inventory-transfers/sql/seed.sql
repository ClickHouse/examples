\set ON_ERROR_STOP on
BEGIN;
INSERT INTO transfers.organizations VALUES ('north', 'North workshop'), ('south', 'South workshop')
ON CONFLICT DO NOTHING;
INSERT INTO transfers.warehouses
SELECT org, warehouse, initcap(warehouse) FROM
  (VALUES ('north'), ('south')) AS o(org),
  (VALUES ('depot'), ('studio'), ('reserve')) AS w(warehouse)
ON CONFLICT DO NOTHING;
INSERT INTO transfers.skus
SELECT org, sku, initcap(sku) FROM
  (VALUES ('north'), ('south')) AS o(org),
  (VALUES ('bolts'), ('panels')) AS s(sku)
ON CONFLICT DO NOTHING;
INSERT INTO transfers.balances
SELECT w.organization, w.id, s.id, 1000
FROM transfers.warehouses w JOIN transfers.skus s USING (organization)
ON CONFLICT DO NOTHING;
COMMIT;
