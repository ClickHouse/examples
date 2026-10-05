import DataLoader from "dataloader";
import { inArray, asc } from "drizzle-orm";
import type { Pool } from "pg";
import { database } from "./database";
import { variants, type Variant } from "./tables";
export function context(pool: Pool) {
  const count = { reads: 0 };
  const db = database(pool, count);
  const variantLoader = new DataLoader<string, Variant[]>(async (ids) => {
    const rows = await db
      .select()
      .from(variants)
      .where(inArray(variants.productId, [...ids]))
      .orderBy(asc(variants.sku));
    return ids.map((id) => rows.filter((row) => row.productId === id));
  });
  return { db, count, variantLoader };
}
export type Context = ReturnType<typeof context>;
