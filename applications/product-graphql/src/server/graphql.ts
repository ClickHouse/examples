import SchemaBuilder from "@pothos/core";
import { asc, eq, ilike, and } from "drizzle-orm";
import type { Context } from "./context";
import { products, collections, type Product, type Variant } from "./tables";
import {
  readCollections,
  type CollectionSnapshot,
  createCollection,
  replaceCollection,
} from "./collections";
import { page, uuid, bad } from "./validation";
const builder = new SchemaBuilder<{
  Context: Context;
  DefaultFieldNullability: false;
}>({ defaultFieldNullability: false });
const VariantRef = builder.objectRef<Variant>("Variant").implement({
  fields: (t) => ({
    id: t.exposeID("id"),
    name: t.exposeString("name"),
    sku: t.exposeString("sku"),
    priceCents: t.exposeInt("priceCents"),
  }),
});
const ProductRef = builder.objectRef<Product>("Product").implement({
  fields: (t) => ({
    id: t.exposeID("id"),
    name: t.exposeString("name"),
    category: t.exposeString("category"),
    description: t.exposeString("description"),
    variants: t.field({
      type: [VariantRef],
      resolve: (product, _args, ctx) => ctx.variantLoader.load(product.id),
    }),
  }),
});
const CollectionRef = builder
  .objectRef<CollectionSnapshot>("Collection")
  .implement({
    fields: (t) => ({
      id: t.exposeID("id"),
      title: t.exposeString("title"),
      revision: t.exposeInt("revision"),
      products: t.field({
        type: [ProductRef],
        resolve: (collection) => collection.products,
      }),
    }),
  });
const Status = builder.enumType("SaveStatus", {
  values: ["OK", "CONFLICT"] as const,
});
const SaveRef = builder
  .objectRef<{
    status: "OK" | "CONFLICT";
    collection: CollectionSnapshot | null;
  }>("CollectionSave")
  .implement({
    fields: (t) => ({
      status: t.field({ type: Status, resolve: (r) => r.status }),
      collection: t.field({
        type: CollectionRef,
        nullable: true,
        resolve: (r) => r.collection,
      }),
    }),
  });
builder.queryType({
  fields: (t) => ({
    products: t.field({
      type: [ProductRef],
      args: {
        first: t.arg.int({ required: true }),
        offset: t.arg.int({ required: true }),
        search: t.arg.string(),
        category: t.arg.string(),
      },
      resolve: (_root, args, ctx) => {
        page(args.first, args.offset);
        if ((args.search?.length ?? 0) > 60) bad("Search is too long");
        if (
          args.category &&
          !["Desk", "Travel", "Lighting"].includes(args.category)
        )
          bad("Unknown category");
        return ctx.db
          .select()
          .from(products)
          .where(
            and(
              args.search
                ? ilike(
                    products.name,
                    "%" + args.search.replace(/[\\%_]/g, "\\$&") + "%",
                  )
                : undefined,
              args.category ? eq(products.category, args.category) : undefined,
            ),
          )
          .orderBy(asc(products.name), asc(products.id))
          .limit(args.first)
          .offset(args.offset);
      },
    }),
    collections: t.field({
      type: [CollectionRef],
      resolve: (_r, _a, ctx) => readCollections(ctx.db),
    }),
    collection: t.field({
      type: CollectionRef,
      nullable: true,
      args: { id: t.arg.id({ required: true }) },
      resolve: async (_r, args, ctx) =>
        (await readCollections(ctx.db, uuid(args.id)))[0] ?? null,
    }),
  }),
});
builder.mutationType({
  fields: (t) => ({
    createCollection: t.field({
      type: CollectionRef,
      args: {
        title: t.arg.string({ required: true }),
        productIds: t.arg.idList({ required: true }),
      },
      resolve: (_r, args, ctx) =>
        createCollection(ctx.db, args.title, args.productIds),
    }),
    replaceCollection: t.field({
      type: SaveRef,
      args: {
        id: t.arg.id({ required: true }),
        baseRevision: t.arg.int({ required: true }),
        productIds: t.arg.idList({ required: true }),
      },
      resolve: (_r, args, ctx) =>
        replaceCollection(ctx.db, args.id, args.baseRevision, args.productIds),
    }),
  }),
});
export const schema = builder.toSchema();
