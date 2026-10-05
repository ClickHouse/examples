import { sql, type Kysely } from "kysely";
import { Migrator } from "kysely/migration";
import { createDb } from "../src/server/db";
const db = createDb();
const migrator = new Migrator({
  db,
  migrationTableSchema: "quote_catalogue",
  provider: {
    async getMigrations() {
      return {
        "001_catalogue": {
          async up(db: Kysely<unknown>) {
            await sql`CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT NOT NULL, category TEXT NOT NULL,
      description TEXT NOT NULL, rate_minor INTEGER NOT NULL CHECK (rate_minor BETWEEN 0 AND 50000))`.execute(
              db,
            );
            await sql`CREATE TABLE quotes (id INTEGER PRIMARY KEY, title TEXT NOT NULL, days INTEGER NOT NULL DEFAULT 1 CHECK (days BETWEEN 1 AND 14),
      revision INTEGER NOT NULL DEFAULT 0 CHECK (revision >= 0), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW())`.execute(
              db,
            );
            await sql`CREATE TABLE quote_lines (quote_id INTEGER REFERENCES quotes(id) ON DELETE CASCADE, product_id INTEGER REFERENCES products(id),
      quantity INTEGER NOT NULL CHECK (quantity BETWEEN 1 AND 20), unit_minor INTEGER NOT NULL CHECK (unit_minor BETWEEN 0 AND 50000),
      PRIMARY KEY (quote_id, product_id))`.execute(db);
          },
        },
      };
    },
  },
});
try {
  const result = await migrator.migrateToLatest();
  if (result.error) throw result.error;
  console.log(
    "Migrations applied",
    result.results?.map((r) => r.status),
  );
} finally {
  await db.destroy();
}
