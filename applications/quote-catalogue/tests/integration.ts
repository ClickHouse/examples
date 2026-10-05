import assert from "node:assert/strict";
import { sql } from "kysely";
import { client, owner, start, stop } from "./helpers";
import { createDb } from "../src/server/db";
import type { SaveInput } from "../src/lib/contract";
const db = owner();
const runtime = createDb();
const id = 900000 + Math.floor(Math.random() * 90000);
const p1 = id,
  p2 = id + 100000;
let server: Awaited<ReturnType<typeof start>> | undefined;
const save = (value: unknown) => client.save(value as SaveInput);
const bad = async (value: unknown) =>
  assert.rejects(
    save(value),
    (error: unknown) => (error as { code?: string }).code === "BAD_REQUEST",
  );
try {
  await db
    .insertInto("products")
    .values([
      {
        id: p1,
        name: "Fixture camera",
        category: "Camera",
        description: "Owned test fixture",
        rate_minor: 3600,
      },
      {
        id: p2,
        name: "Fixture stand",
        category: "Support",
        description: "Owned test fixture",
        rate_minor: 800,
      },
    ])
    .execute();
  await db
    .insertInto("quotes")
    .values({
      id,
      title: "Owned integration fixture",
      days: 1,
      revision: 0,
      updated_at: new Date().toISOString(),
    })
    .execute();
  server = await start();
  const input = {
    id,
    revision: 0,
    days: 3,
    lines: [
      { productId: p1, quantity: 2 },
      { productId: p2, quantity: 1 },
    ],
  };
  await bad({ ...input, days: 0 });
  await bad({ ...input, days: 1.5 });
  await bad({ ...input, totalMinor: 1 });
  await bad({ ...input, lines: [{ productId: p1, quantity: -1 }] });
  await bad({ ...input, lines: [{ productId: p1, quantity: 1.1 }] });
  await bad({ ...input, lines: [{ productId: p1, quantity: 21 }] });
  await bad({ ...input, lines: [] });
  await bad({
    ...input,
    lines: [{ productId: p1, quantity: 1, unitMinor: 1 }],
  });
  await bad({
    ...input,
    lines: [
      { productId: p1, quantity: 1 },
      { productId: p1, quantity: 2 },
    ],
  });
  await bad({ ...input, lines: [{ productId: 2000000000, quantity: 1 }] });
  const races = await Promise.allSettled([
    client.save(input),
    client.save(input),
  ]);
  assert.equal(races.filter((r) => r.status === "fulfilled").length, 1);
  assert.equal(
    (races.find((r) => r.status === "rejected") as PromiseRejectedResult).reason
      .code,
    "CONFLICT",
  );
  const saved = await client.get({ id });
  assert.equal(saved.totalMinor, 24000);
  assert.equal(saved.revision, 1);
  await stop(server);
  server = await start();
  assert.deepEqual(await client.get({ id }), saved);
  console.log(
    "PASS actual oRPC/ArkType invalid inputs and product references; competing saves; genuine process restart; server-derived £240.00",
  );
  // A product rate change does not rewrite saved line snapshots. A later save reprices the full quote.
  await db
    .updateTable("products")
    .set({ rate_minor: 4000 })
    .where("id", "=", p1)
    .execute();
  assert.equal((await client.get({ id })).totalMinor, 24000);
  const repriced = await client.save({ ...input, revision: 1 });
  assert.equal(repriced.totalMinor, 26400);
  await sql`ALTER TABLE quote_lines ADD CONSTRAINT quote_fixture_failure CHECK (quote_id <> ${sql.lit(id)} OR quantity <> 19)`.execute(
    db,
  );
  await assert.rejects(
    client.save({
      ...input,
      revision: 2,
      days: 4,
      lines: [
        { productId: p1, quantity: 1 },
        { productId: p2, quantity: 19 },
      ],
    }),
  );
  assert.deepEqual(await client.get({ id }), repriced);
  await sql`ALTER TABLE quote_lines DROP CONSTRAINT quote_fixture_failure`.execute(
    db,
  );
  console.log(
    "PASS saved rate snapshots, full server repricing, failed line write restores old lines and header revision",
  );
  await assert.rejects(
    runtime
      .updateTable("products")
      .set({ rate_minor: 1 })
      .where("id", "=", p1)
      .execute(),
    /permission denied/,
  );
  await assert.rejects(
    runtime.deleteFrom("quotes").where("id", "=", id).execute(),
    /permission denied/,
  );
  await assert.rejects(
    sql`CREATE TABLE quote_catalogue.forbidden_fixture (id integer)`.execute(
      runtime,
    ),
    /permission denied/,
  );
  console.log(
    "PASS restricted runtime denies catalogue prices, quote deletion and schema creation",
  );
} finally {
  await stop(server);
  await sql`ALTER TABLE quote_lines DROP CONSTRAINT IF EXISTS quote_fixture_failure`.execute(
    db,
  );
  await db.deleteFrom("quotes").where("id", "=", id).execute();
  await db.deleteFrom("products").where("id", "in", [p1, p2]).execute();
  await db.destroy();
  await runtime.destroy();
}
