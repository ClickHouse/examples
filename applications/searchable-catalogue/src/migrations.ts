import { sql, type Kysely } from 'kysely';
import type { Migration } from 'kysely/migration';

export const initial: Migration = {
  async up(db: Kysely<any>) {
    await sql`CREATE TABLE catalogue.products (
      id UUID PRIMARY KEY,
      sku TEXT NOT NULL UNIQUE CHECK (length(sku) BETWEEN 1 AND 40),
      name TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 160),
      description TEXT NOT NULL CHECK (length(description) <= 4000),
      category TEXT NOT NULL CHECK (category IN ('camping', 'clothing', 'cycling')),
      price_pence INTEGER NOT NULL CHECK (price_pence BETWEEN 0 AND 100000000),
      active BOOLEAN NOT NULL DEFAULT true,
      search_document TSVECTOR GENERATED ALWAYS AS
        (to_tsvector('english', name || ' ' || description)) STORED
    )`.execute(db);
    await sql`CREATE INDEX products_search ON catalogue.products USING GIN (search_document)`.execute(db);
    await sql`CREATE INDEX products_price ON catalogue.products (price_pence, id) WHERE active`.execute(db);
    await sql`CREATE INDEX products_category_price ON catalogue.products (category, price_pence, id) WHERE active`.execute(db);
    await sql`GRANT SELECT ON catalogue.products TO catalogue_reader`.execute(db);
  },
  async down(db: Kysely<any>) { await sql`DROP TABLE catalogue.products`.execute(db); },
};
