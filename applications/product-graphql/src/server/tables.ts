import {
  pgSchema,
  uuid,
  text,
  integer,
  primaryKey,
  unique,
} from "drizzle-orm/pg-core";
const s = pgSchema("product_catalog");
export const products = s.table("products", {
  id: uuid().primaryKey(),
  name: text().notNull(),
  category: text().notNull(),
  description: text().notNull(),
});
export const variants = s.table("variants", {
  id: uuid().primaryKey(),
  productId: uuid("product_id")
    .notNull()
    .references(() => products.id),
  name: text().notNull(),
  sku: text().notNull(),
  priceCents: integer("price_cents").notNull(),
});
export const collections = s.table("collections", {
  id: uuid().primaryKey(),
  title: text().notNull(),
  revision: integer().notNull(),
});
export const items = s.table(
  "collection_items",
  {
    collectionId: uuid("collection_id")
      .notNull()
      .references(() => collections.id, { onDelete: "cascade" }),
    productId: uuid("product_id")
      .notNull()
      .references(() => products.id),
    position: integer().notNull(),
  },
  (t) => [
    primaryKey({ columns: [t.collectionId, t.productId] }),
    unique().on(t.collectionId, t.position),
  ],
);
export type Product = typeof products.$inferSelect;
export type Variant = typeof variants.$inferSelect;
export type Collection = typeof collections.$inferSelect;
