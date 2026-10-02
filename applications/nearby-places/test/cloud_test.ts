import assert from "node:assert/strict";
import postgres from "postgres";
import { database, databaseOptions } from "../src/database.ts";
import { nearbyQuery } from "../src/places.ts";
import type { Search } from "../src/input.ts";
const search = (
  longitude = 0,
  latitude = 0,
  radiusMeters = 1200,
  extra: Partial<Search> = {},
): Search => ({ longitude, latitude, radiusMeters, limit: 20, ...extra });
async function withDatabase(fn: (sql: ReturnType<typeof database>) => Promise<void>) {
  const sql = database();
  try {
    await fn(sql);
  } finally {
    await sql.end({ timeout: 5 });
  }
}
Deno.test("geography meters, zero distance and independently known equatorial distances", async () => {
  await withDatabase(async (sql) => {
    const places = await nearbyQuery(sql, search());
    assert.deepEqual(places.map((p) => p.id), [6, 8, 7]);
    assert.equal(places[0].distanceMeters, 0);
    assert(Math.abs(places[2].distanceMeters - 1113.194908) < 0.1);
    assert(Math.abs(places[1].distanceMeters - 1105.742758) < 0.1);
    console.log(
      "Equatorial meters:",
      places.map(({ id, distanceMeters }) => ({ id, distanceMeters })),
    );
    const zero = await nearbyQuery(sql, search(0, 0, 0));
    assert.deepEqual(zero.map((p) => p.id), [6]);
  });
});
Deno.test("radius inclusion/exclusion and category filtering use exact geography predicates", async () => {
  await withDatabase(async (sql) => {
    assert.deepEqual((await nearbyQuery(sql, search(0, 0, 1110))).map((p) => p.id), [6, 8]);
    assert.deepEqual((await nearbyQuery(sql, search(0, 0, 1114))).map((p) => p.id), [6, 8, 7]);
    assert.deepEqual(
      (await nearbyQuery(sql, search(0, 0, 1200, { category: "cafe" }))).map((p) => p.id),
      [7],
    );
    assert.equal((await nearbyQuery(sql, search(0, 0, 1, { category: "park" }))).length, 0);
  });
});
Deno.test("longitude precedes latitude and equal distances use stable ID ordering/limit", async () => {
  await withDatabase(async (sql) => {
    const correct = await nearbyQuery(sql, search(12, 45, 0));
    assert.equal(correct[0].id, 11);
    assert.equal(correct[0].longitude, 12);
    assert.equal(correct[0].latitude, 45);
    assert.equal((await nearbyQuery(sql, search(45, 12, 1000))).length, 0);
    const ties = await nearbyQuery(sql, search(-0.12, 51.5, 0));
    assert.deepEqual(ties.map((p) => p.id), [1, 4]);
    assert.deepEqual(
      (await nearbyQuery(sql, search(-0.12, 51.5, 0, { limit: 1 }))).map((p) => p.id),
      [1],
    );
    const again = await nearbyQuery(sql, search(-0.12, 51.5, 0));
    assert.deepEqual(again, ties);
  });
});
Deno.test("antimeridian proximity and polar coordinates remain geographic", async () => {
  await withDatabase(async (sql) => {
    const crossing = await nearbyQuery(sql, search(179.999, 0, 300));
    assert.deepEqual(crossing.map((p) => p.id), [9, 10]);
    assert(Math.abs(crossing[1].distanceMeters - 222.638982) < 0.1);
    assert.deepEqual((await nearbyQuery(sql, search(179.999, 0, 200))).map((p) => p.id), [9]);
    assert.equal((await nearbyQuery(sql, search(0, 90, 200)))[0].id, 12);
    console.log("Antimeridian distanceMeters:", crossing[1].distanceMeters);
  });
});
Deno.test("runtime role stays read-only even if its session read-only default is disabled", async () => {
  await withDatabase(async (sql) => {
    assert.equal((await sql`SELECT current_user AS role`)[0].role, "places_reader");
    assert.equal(
      (await sql`SHOW default_transaction_read_only`)[0].default_transaction_read_only,
      "on",
    );
    await sql`SET default_transaction_read_only = off`;
    for (
      const statement of [
        "INSERT INTO nearby_places.places SELECT * FROM nearby_places.places WHERE false",
        "UPDATE nearby_places.places SET name='changed' WHERE false",
        "DELETE FROM nearby_places.places WHERE false",
        "CREATE TABLE nearby_places.forbidden(id int)",
        "CREATE SCHEMA runtime_forbidden",
        "CREATE TEMP TABLE runtime_forbidden(id int)",
        "UPDATE nearby_places.schema_migrations SET version=version WHERE false",
      ]
    ) {
      await assert.rejects(
        sql.unsafe(statement),
        (e: unknown) => (e as { code?: string }).code === "42501",
      );
    }
    assert.equal(
      (await sql`SELECT count(*)::integer AS count FROM nearby_places.places`)[0].count,
      12,
    );
  });
});
Deno.test("Cloud CA and hostname controls reject wrong trust and wrong hostname", async () => {
  const options = databaseOptions();
  const dir = await Deno.makeTempDir();
  try {
    const output = await new Deno.Command("openssl", {
      args: [
        "req",
        "-x509",
        "-newkey",
        "rsa:2048",
        "-nodes",
        "-keyout",
        `${dir}/key.pem`,
        "-out",
        `${dir}/ca.pem`,
        "-days",
        "1",
        "-subj",
        "/CN=unrelated-test-ca",
      ],
      stdout: "null",
      stderr: "null",
    }).output();
    assert(output.success);
    for (
      const [ssl, expected] of [
        [
          { ...options.ssl, ca: await Deno.readTextFile(`${dir}/ca.pem`) },
          /CERT|issuer|certificate|UnknownIssuer|CaUsedAsEndEntity/i,
        ],
        [
          { ...options.ssl, servername: "wrong-hostname.example.test" },
          /ALTNAME|hostname|certificate|NotValidForName/i,
        ],
      ] as const
    ) {
      const bad = postgres({ ...options, ssl, max: 1 });
      try {
        await assert.rejects(bad`SELECT 1`, (e: unknown) => {
          const error = e as { code?: string; message: string };
          console.log("Negative TLS control", error.code ?? "no-code", error.message.split(":")[0]);
          return expected.test(`${error.code} ${error.message}`);
        });
      } finally {
        await bad.end({ timeout: 1 });
      }
    }
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
  await withDatabase(async (sql) =>
    assert.equal((await sql`SELECT 1 AS positive_control`)[0].positive_control, 1)
  );
});
Deno.test("real EXPLAIN uses the exact application query without forcing an index", async () => {
  await withDatabase(async (sql) => {
    const query = nearbyQuery(sql, search(-0.12, 51.5, 1000));
    const rows = await sql`EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ${query}`;
    const plan = rows[0]["QUERY PLAN"];
    const text = JSON.stringify(plan, null, 2);
    assert(/st_dwithin/i.test(text));
    const directory = Deno.env.get("EVIDENCE_DIR");
    if (directory) await Deno.writeTextFile(`${directory}/explain.json`, text + "\n");
    console.log("Actual plan:", text);
  });
});
