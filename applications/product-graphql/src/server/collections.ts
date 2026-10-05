import { and, eq, inArray, asc } from "drizzle-orm";
import type { Database } from "./database";
import {
  products,
  collections,
  items,
  type Product,
  type Collection,
} from "./tables";
import { contents, uuid, title, revision, bad } from "./validation";
export type CollectionSnapshot = Collection & { products: Product[] };
async function known(tx: Pick<Database, "select">, ids: string[]) {
  const rows = ids.length
    ? await tx.select().from(products).where(inArray(products.id, ids))
    : [];
  if (rows.length !== ids.length) bad("A chosen product no longer exists");
  return ids.map((id) => rows.find((row) => row.id === id)!);
}
export async function readCollections(
  db: Database,
  id?: string,
): Promise<CollectionSnapshot[]> {
  return db.transaction(
    async (tx) => {
      const headers = await tx
        .select()
        .from(collections)
        .where(id ? eq(collections.id, uuid(id)) : undefined)
        .orderBy(asc(collections.title), asc(collections.id))
        .limit(20);
      if (!headers.length) return [];
      const rows = await tx
        .select({ collectionId: items.collectionId, product: products })
        .from(items)
        .innerJoin(products, eq(items.productId, products.id))
        .where(
          inArray(
            items.collectionId,
            headers.map((row) => row.id),
          ),
        )
        .orderBy(asc(items.position));
      return headers.map((header) => ({
        ...header,
        products: rows
          .filter((row) => row.collectionId === header.id)
          .map((row) => row.product),
      }));
    },
    { isolationLevel: "repeatable read", accessMode: "read only" },
  );
}
export async function createCollection(
  db: Database,
  name: string,
  ids: string[],
) {
  ids = contents(ids);
  name = title(name);
  return db.transaction(async (tx) => {
    const selected = await known(tx, ids);
    const [row] = await tx
      .insert(collections)
      .values({ id: crypto.randomUUID(), title: name, revision: 1 })
      .returning();
    if (ids.length)
      await tx.insert(items).values(
        ids.map((productId, position) => ({
          collectionId: row.id,
          productId,
          position,
        })),
      );
    return { ...row, products: selected };
  });
}
export async function replaceCollection(
  db: Database,
  id: string,
  base: number,
  ids: string[],
) {
  uuid(id);
  revision(base);
  ids = contents(ids);
  return db.transaction(async (tx) => {
    const [row] = await tx
      .update(collections)
      .set({ revision: base + 1 })
      .where(and(eq(collections.id, id), eq(collections.revision, base)))
      .returning();
    if (!row) return { status: "CONFLICT" as const, collection: null };
    const selected = await known(tx, ids);
    await tx.delete(items).where(eq(items.collectionId, id));
    if (ids.length)
      await tx.insert(items).values(
        ids.map((productId, position) => ({
          collectionId: id,
          productId,
          position,
        })),
      );
    return {
      status: "OK" as const,
      collection: { ...row, products: selected },
    };
  });
}
