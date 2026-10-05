\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE intake_owner;
INSERT INTO intake.batches (id,fingerprint,filename,format,headers,row_count,supplier,status,revision)
VALUES ('10000000-0000-4000-8000-000000000001',repeat('0',64),'Built-in catalog.csv','csv','["SKU","Product","Price","Stock"]',2,'Willow Cooperative','promoted',3) ON CONFLICT DO NOTHING;
INSERT INTO intake.staging_rows (batch_id,row_number,raw_values,mapped_values)
VALUES ('10000000-0000-4000-8000-000000000001',2,'{"SKU":"BASE001"}','{"sku":"BASE001","product":"Cotton market tote","cents":1250,"stock":40}'),
('10000000-0000-4000-8000-000000000001',3,'{"SKU":"BASE002"}','{"sku":"BASE002","product":"Linen tea towel","cents":800,"stock":75}') ON CONFLICT DO NOTHING;
INSERT INTO intake.products (batch_id,row_number,supplier,supplier_key,sku,product,price_cents,stock)
SELECT batch_id,row_number,'Willow Cooperative','willow cooperative',mapped_values->>'sku',mapped_values->>'product',(mapped_values->>'cents')::integer,(mapped_values->>'stock')::integer FROM intake.staging_rows WHERE batch_id='10000000-0000-4000-8000-000000000001' ON CONFLICT DO NOTHING;
COMMIT;
