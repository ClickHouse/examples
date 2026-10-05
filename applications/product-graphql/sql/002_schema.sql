\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE catalog_owner;
CREATE TABLE product_catalog.products(id UUID PRIMARY KEY,name TEXT NOT NULL CHECK(length(name) BETWEEN 1 AND 80),category TEXT NOT NULL CHECK(category IN ('Desk','Travel','Lighting')),description TEXT NOT NULL);
CREATE TABLE product_catalog.variants(id UUID PRIMARY KEY,product_id UUID NOT NULL REFERENCES product_catalog.products(id),name TEXT NOT NULL,sku TEXT NOT NULL UNIQUE,price_cents INTEGER NOT NULL CHECK(price_cents BETWEEN 1 AND 1000000),position INTEGER NOT NULL CHECK(position BETWEEN 0 AND 2),UNIQUE(product_id,position));
CREATE TABLE product_catalog.collections(id UUID PRIMARY KEY,title TEXT NOT NULL CHECK(length(btrim(title)) BETWEEN 1 AND 60),revision INTEGER NOT NULL CHECK(revision>0));
CREATE TABLE product_catalog.collection_items(collection_id UUID NOT NULL REFERENCES product_catalog.collections(id) ON DELETE CASCADE,product_id UUID NOT NULL REFERENCES product_catalog.products(id),position INTEGER NOT NULL CHECK(position BETWEEN 0 AND 11),PRIMARY KEY(collection_id,product_id),UNIQUE(collection_id,position));
GRANT SELECT ON ALL TABLES IN SCHEMA product_catalog TO catalog_app;
GRANT INSERT ON product_catalog.collections,product_catalog.collection_items TO catalog_app;
GRANT UPDATE(revision) ON product_catalog.collections TO catalog_app;
GRANT DELETE ON product_catalog.collection_items TO catalog_app;
COMMIT;
