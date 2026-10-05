import {
  beforeAll,
  afterAll,
  beforeEach,
  afterEach,
  test,
  expect,
} from "bun:test";
import { setDefaultTimeout } from "bun:test";
setDefaultTimeout(30000);
import { graphql, execute } from "graphql";
import { createYoga } from "graphql-yoga";
import { connectDatabase } from "../src/server/database";
import { context } from "../src/server/context";
import { schema } from "../src/server/graphql";
import { CatalogDocument } from "../src/client/gql/graphql";
import type { Pool } from "pg";
let pool: Pool;
let admin: Pool;
let id: string;
const p1 = "10000000-0000-4000-8000-000000000001",
  p2 = "10000000-0000-4000-8000-000000000002";
beforeAll(async () => {
  pool = await connectDatabase();
  if (!process.env.DATABASE_TEST_ADMIN_URL)
    throw new Error("Dedicated migration test login required");
  admin = await connectDatabase(process.env.DATABASE_TEST_ADMIN_URL);
});
afterAll(async () => {
  await pool?.end();
  await admin?.end();
});
beforeEach(async () => {
  id = crypto.randomUUID();
  const c = await admin.connect();
  try {
    await c.query("BEGIN");
    await c.query("SET LOCAL ROLE catalog_owner");
    await c.query(
      "INSERT INTO product_catalog.collections VALUES($1,'Test collection',1)",
      [id],
    );
    await c.query(
      "INSERT INTO product_catalog.collection_items VALUES($1,$2,0)",
      [id, p1],
    );
    await c.query("COMMIT");
  } finally {
    c.release();
  }
});
afterEach(async () => {
  const c = await admin.connect();
  try {
    await c.query("BEGIN");
    await c.query("SET LOCAL ROLE catalog_owner");
    await c.query("DELETE FROM product_catalog.collections WHERE id=$1", [id]);
    await c.query("COMMIT");
  } finally {
    c.release();
  }
});
const mutation = `mutation Save($id:ID!,$base:Int!,$ids:[ID!]!){replaceCollection(id:$id,baseRevision:$base,productIds:$ids){status collection{id revision products{id}}}}`;
const run = (source: string, variables: Record<string, unknown> = {}) =>
  graphql({
    schema,
    source,
    variableValues: variables,
    contextValue: context(pool),
  });
const save = (ids: string[], base = 1) => run(mutation, { id, base, ids });
test("nested catalog is two SQL SELECTs for 1,12 and20 products", async () => {
  for (const first of [1, 12, 20]) {
    const ctx = context(pool);
    const result = await execute({
      schema,
      document: CatalogDocument,
      variableValues: { first, offset: 0 },
      contextValue: ctx,
    });
    expect(result.errors).toBeUndefined();
    expect((result.data?.products as unknown[]).length).toBe(first);
    expect(ctx.count.reads).toBe(2);
    console.log(
      `Catalog ${first} products + variants: ${ctx.count.reads} SQL SELECTs`,
    );
  }
});
test("eight concurrent replacements commit exactly one revision", async () => {
  const results = await Promise.all(
    Array.from({ length: 8 }, () => save([p2, p1])),
  );
  expect(results.every((x) => !x.errors)).toBe(true);
  const statuses = results.map(
    (x) => (x.data?.replaceCollection as { status: string }).status,
  );
  expect(statuses.filter((x) => x === "OK")).toHaveLength(1);
  expect(statuses.filter((x) => x === "CONFLICT")).toHaveLength(7);
  const row = await pool.query(
    "SELECT revision FROM product_catalog.collections WHERE id=$1",
    [id],
  );
  expect(row.rows[0].revision).toBe(2);
  const items = await pool.query(
    "SELECT product_id FROM product_catalog.collection_items WHERE collection_id=$1 ORDER BY position",
    [id],
  );
  expect(items.rows.map((r) => r.product_id)).toEqual([p2, p1]);
});
test("unknown product rolls version and replacement back", async () => {
  const result = await save([p2, crypto.randomUUID()]);
  expect(result.errors?.[0].extensions.code).toBe("BAD_USER_INPUT");
  expect(
    (
      await pool.query(
        "SELECT revision FROM product_catalog.collections WHERE id=$1",
        [id],
      )
    ).rows[0].revision,
  ).toBe(1);
  expect(
    (
      await pool.query(
        "SELECT product_id FROM product_catalog.collection_items WHERE collection_id=$1",
        [id],
      )
    ).rows[0].product_id,
  ).toBe(p1);
});
test("invalid contents and page return explicit errors", async () => {
  expect((await save([p1, p1])).errors?.[0].extensions.code).toBe(
    "BAD_USER_INPUT",
  );
  expect(
    (await save(Array.from({ length: 13 }, () => crypto.randomUUID())))
      .errors?.[0].extensions.code,
  ).toBe("BAD_USER_INPUT");
  expect(
    (await run("{products(first:21,offset:0){id}}")).errors?.[0].extensions
      .code,
  ).toBe("BAD_USER_INPUT");
});
test("runtime cannot alter catalog, schema or collection title", async () => {
  await expect(
    pool.query("CREATE TABLE product_catalog.forbidden(id int)"),
  ).rejects.toThrow();
  await expect(
    pool.query("UPDATE product_catalog.products SET name='Other' WHERE id=$1", [
      p1,
    ]),
  ).rejects.toThrow();
  await expect(
    pool.query(
      "UPDATE product_catalog.collections SET title='Other' WHERE id=$1",
      [id],
    ),
  ).rejects.toThrow();
});
test("Yoga serves the real generated nested operation", async () => {
  const yoga = createYoga({
    schema,
    logging: false,
    context: () => context(pool),
  });
  const response = await yoga.fetch("http://localhost/graphql", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      query: "{products(first:2,offset:0){name variants{sku priceCents}}}",
    }),
  });
  const result = await response.json();
  expect(result.errors).toBeUndefined();
  expect(result.data.products).toHaveLength(2);
  expect(result.data.products[0].variants).toHaveLength(3);
});

test("collection reads retain matching revision and ordered items during replacements", async () => {
  const writer = (async () => {
    for (let base = 1; base <= 12; base++) {
      const result = await save([(base + 1) % 2 === 0 ? p2 : p1], base);
      expect(result.errors).toBeUndefined();
    }
  })();
  for (let n = 0; n < 24; n++) {
    const result = await run(
      "query Read($id:ID!){collection(id:$id){revision products{id}}}",
      { id },
    );
    expect(result.errors).toBeUndefined();
    const collection = result.data?.collection as {
      revision: number;
      products: { id: string }[];
    };
    expect(collection.products.map((p) => p.id)).toEqual([
      collection.revision % 2 === 0 ? p2 : p1,
    ]);
  }
  await writer;
});
