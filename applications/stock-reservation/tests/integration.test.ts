import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import type { SQL } from "bun";
import { createApp } from "../src/app";
import { createDatabase } from "../src/database";

// Run against a disposable, migrated managed Postgres database. Both app
// instances use the restricted runtime role; only fixture setup uses admin.
const run = crypto.randomUUID().replaceAll("-", "").slice(0, 16);
const clientA = `test-a-${run}`;
const clientB = `test-b-${run}`;
const tokenA = crypto.randomUUID();
const tokenB = crypto.randomUUID();
const apiKeys = new Map([[clientA, tokenA], [clientB, tokenB]]);
const fixtureSkus: string[] = [];
const applicationErrors: unknown[] = [];
let admin: SQL;
let databaseA: SQL;
let databaseB: SQL;
let appA: ReturnType<typeof createApp>;
let appB: ReturnType<typeof createApp>;

type Reservation = {
  id: string;
  sku: string;
  quantity: number;
  status: "active" | "released";
  created_at: string;
  released_at: string | null;
};

function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Integration tests require ${name}; see tests/README.md.`);
  return value;
}

async function request(
  path: string,
  options: RequestInit = {},
  token: string | null = tokenA,
  secondInstance = false,
): Promise<Response> {
  const headers = new Headers(options.headers);
  if (token !== null) headers.set("Authorization", `Bearer ${token}`);
  return (secondInstance ? appB : appA).request(path, { ...options, headers });
}

function reserve(
  sku: string,
  quantity: number,
  key: string = crypto.randomUUID(),
  token = tokenA,
  secondInstance = false,
): Promise<Response> {
  return request("/reservations", {
    method: "POST",
    headers: { "Content-Type": "application/json", "Idempotency-Key": key },
    body: JSON.stringify({ sku, quantity }),
  }, token, secondInstance);
}

async function fixture(label: string, stock: number): Promise<string> {
  const sku = `test-${label}-${run}`;
  await admin`
    INSERT INTO stock_reservation.inventory (sku, name, available)
    VALUES (${sku}, ${`Integration fixture: ${label}`}, ${stock})
  `;
  fixtureSkus.push(sku);
  return sku;
}

async function stock(sku: string): Promise<number> {
  const [row] = await admin`
    SELECT available FROM stock_reservation.inventory WHERE sku = ${sku}
  `;
  return row.available;
}

async function counts(sku: string): Promise<{ reservations: number; keys: number }> {
  const [row] = await admin`
    SELECT
      (SELECT count(*)::int FROM stock_reservation.reservations WHERE sku = ${sku}) AS reservations,
      (SELECT count(*)::int FROM stock_reservation.idempotency_keys WHERE request_sku = ${sku}) AS keys
  `;
  return row;
}

async function expectError(response: Response, status: number, code: string): Promise<void> {
  expect(response.status).toBe(status);
  expect(response.headers.get("content-type")).toContain("application/json");
  const body = await response.json();
  expect(body.error.code).toBe(code);
  expect(typeof body.error.message).toBe("string");
}

beforeAll(async () => {
  const caCertPath = required("PG_CA_CERT_PATH");
  const url = required("DATABASE_URL");
  const adminUrl = required("TEST_ADMIN_DATABASE_URL");
  admin = await createDatabase({ url: adminUrl, caCertPath, maxConnections: 2 });
  databaseA = await createDatabase({ url, caCertPath, maxConnections: 4 });
  databaseB = await createDatabase({ url, caCertPath, maxConnections: 4 });
  const [[adminIdentity], [runtimeIdentity]] = await Promise.all([
    admin`SELECT current_user AS name`,
    databaseA`SELECT current_user AS name`,
  ]);
  if (adminIdentity.name === runtimeIdentity.name) {
    throw new Error("DATABASE_URL must use the restricted runtime role, not the fixture administrator.");
  }
  appA = createApp({ sql: databaseA, apiKeys, onError: (error) => applicationErrors.push(error) });
  appB = createApp({ sql: databaseB, apiKeys, onError: (error) => applicationErrors.push(error) });
}, 30_000);

afterAll(async () => {
  try {
    if (admin && fixtureSkus.length > 0) {
      await admin.begin(async (tx) => {
        await tx`
          DELETE FROM stock_reservation.idempotency_keys
          WHERE client_id IN (${clientA}, ${clientB})
        `;
        await tx`
          DELETE FROM stock_reservation.reservations
          WHERE client_id IN (${clientA}, ${clientB})
        `;
        for (const sku of fixtureSkus) {
          await tx`DELETE FROM stock_reservation.inventory WHERE sku = ${sku}`;
        }
      });
      const [remaining] = await admin`
        SELECT
          (SELECT count(*)::int FROM stock_reservation.reservations
            WHERE client_id IN (${clientA}, ${clientB})) AS reservations,
          (SELECT count(*)::int FROM stock_reservation.idempotency_keys
            WHERE client_id IN (${clientA}, ${clientB})) AS keys
      `;
      expect(remaining).toEqual({ reservations: 0, keys: 0 });
    }
  } finally {
    await Promise.all([admin?.close(), databaseA?.close(), databaseB?.close()]);
  }
}, 30_000);

describe("real Postgres reservation invariants", () => {
  test("uses TLS and a runtime role without administrative/table deletion privileges", async () => {
    const [connection] = await databaseA`
      SELECT ssl, version FROM pg_stat_ssl WHERE pid = pg_backend_pid()
    `;
    expect(connection.ssl).toBe(true);
    expect(connection.version).toMatch(/^TLSv1\.[23]$/);
    const [role] = await databaseA`
      SELECT rolsuper, rolcreatedb, rolcreaterole, rolreplication, rolbypassrls
      FROM pg_roles WHERE rolname = current_user
    `;
    expect(Object.values(role)).toEqual([false, false, false, false, false]);
    const [privileges] = await databaseA`
      SELECT
        has_schema_privilege(current_user, 'stock_reservation', 'CREATE') AS create_schema_objects,
        has_table_privilege(current_user, 'stock_reservation.inventory', 'INSERT') AS insert_inventory,
        has_table_privilege(current_user, 'stock_reservation.inventory', 'DELETE') AS delete_inventory,
        has_table_privilege(current_user, 'stock_reservation.reservations', 'DELETE') AS delete_reservations,
        has_table_privilege(current_user, 'stock_reservation.idempotency_keys', 'DELETE') AS delete_keys,
        has_table_privilege(current_user, 'stock_reservation.inventory', 'TRUNCATE') AS truncate_inventory,
        has_table_privilege(current_user, 'stock_reservation.reservations', 'TRUNCATE') AS truncate_reservations,
        has_table_privilege(current_user, 'stock_reservation.idempotency_keys', 'TRUNCATE') AS truncate_keys
    `;
    expect(Object.values(privileges).every((granted) => granted === false)).toBe(true);
    // Even deleting zero rows must pass PostgreSQL's privilege check.
    // Bun.SQL queries are lazy thenables. Await inside an actual Promise before
    // passing it to a rejection matcher, or the matcher may never run the query.
    await expect((async () => {
      await databaseA`
        DELETE FROM stock_reservation.inventory WHERE sku = ${`absent-${run}`}
      `;
    })()).rejects.toThrow();
  });

  test("requires authentication on every route", async () => {
    const id = crypto.randomUUID();
    for (const [path, method] of [
      ["/inventory", "GET"],
      ["/reservations", "POST"],
      [`/reservations/${id}`, "GET"],
      [`/reservations/${id}`, "DELETE"],
    ]) {
      await expectError(await request(path!, { method }, null), 401, "unauthorized");
      await expectError(await request(path!, { method }, "invalid-token"), 401, "unauthorized");
    }
  });

  test("returns inventory without exposing reservation/client data", async () => {
    const sku = await fixture("inventory", 7);
    const response = await request("/inventory");
    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body.inventory.find((item: { sku: string }) => item.sku === sku)).toEqual({
      sku, name: "Integration fixture: inventory", available: 7,
    });
  });

  test("32 competing buyers across two app instances cannot oversell 9 units", async () => {
    const sku = await fixture("competing", 9);
    const responses = await Promise.all(Array.from({ length: 32 }, (_, index) =>
      reserve(sku, 1, `buyer-${index}-${run}`, tokenA, index % 2 === 1),
    ));
    expect(responses.filter((response) => response.status === 201)).toHaveLength(9);
    expect(responses.filter((response) => response.status === 409)).toHaveLength(23);
    for (const response of responses.filter((response) => response.status === 409)) {
      await expectError(response, 409, "insufficient_inventory");
    }
    expect(await stock(sku)).toBe(0);
    expect(await counts(sku)).toEqual({ reservations: 9, keys: 9 });
    const [totals] = await admin`
      SELECT sum(quantity)::int AS reserved FROM stock_reservation.reservations
      WHERE sku = ${sku} AND status = 'active'
    `;
    expect(totals.reserved).toBe(9);
  }, 30_000);

  test("simultaneous retries share one reservation and the exact original response", async () => {
    const sku = await fixture("same-key", 10);
    const key = `same-key-${run}`;
    const responses = await Promise.all(Array.from({ length: 24 }, (_, index) =>
      reserve(sku, 3, key, tokenA, index % 2 === 1),
    ));
    expect(responses.every((response) => response.status === 201)).toBe(true);
    const responseTexts = await Promise.all(responses.map((response) => response.text()));
    expect(new Set(responseTexts).size).toBe(1);
    const bodies: Reservation[] = responseTexts.map((body) => JSON.parse(body));
    expect(new Set(bodies.map((body) => body.id)).size).toBe(1);
    for (const body of bodies) expect(body).toEqual(bodies[0]!);
    expect(responses.filter((response) => response.headers.get("Idempotency-Replayed") === "true")).toHaveLength(23);
    expect(await stock(sku)).toBe(7);
    expect(await counts(sku)).toEqual({ reservations: 1, keys: 1 });
  }, 30_000);

  test("reusing a key with a changed quantity or SKU conflicts without changing stock", async () => {
    const first = await fixture("conflict-a", 10);
    const second = await fixture("conflict-b", 10);
    const key = `conflict-${run}`;
    expect((await reserve(first, 2, key)).status).toBe(201);
    await expectError(await reserve(first, 3, key), 409, "idempotency_conflict");
    await expectError(await reserve(second, 2, key), 409, "idempotency_conflict");
    expect(await stock(first)).toBe(8);
    expect(await stock(second)).toBe(10);
    expect(await counts(first)).toEqual({ reservations: 1, keys: 1 });
    expect(await counts(second)).toEqual({ reservations: 0, keys: 0 });
  });

  test("concurrent mismatched payloads sharing a key produce one winner", async () => {
    const sku = await fixture("racing-conflict", 10);
    const key = `racing-conflict-${run}`;
    const responses = await Promise.all([
      reserve(sku, 2, key), reserve(sku, 3, key, tokenA, true),
    ]);
    expect(responses.map((response) => response.status).sort()).toEqual([201, 409]);
    const winner = await responses.find((response) => response.status === 201)!.json() as Reservation;
    await expectError(responses.find((response) => response.status === 409)!, 409, "idempotency_conflict");
    expect(await stock(sku)).toBe(10 - winner.quantity);
    expect(await counts(sku)).toEqual({ reservations: 1, keys: 1 });
  });

  test("concurrent release restores stock exactly once; replay preserves the original create result", async () => {
    const sku = await fixture("release", 10);
    const key = `release-${run}`;
    const original = await (await reserve(sku, 4, key)).json() as Reservation;
    const releases = await Promise.all(Array.from({ length: 20 }, (_, index) =>
      request(`/reservations/${original.id}`, { method: "DELETE" }, tokenA, index % 2 === 1),
    ));
    expect(releases.every((response) => response.status === 200)).toBe(true);
    const bodies: Reservation[] = await Promise.all(releases.map((response) => response.json()));
    for (const body of bodies) expect(body).toEqual(bodies[0]!);
    expect(bodies[0]!.status).toBe("released");
    expect(bodies[0]!.released_at).not.toBeNull();
    expect(await stock(sku)).toBe(10);
    const current = await request(`/reservations/${original.id}`);
    expect(current.status).toBe(200);
    expect(await current.json()).toEqual(bodies[0]!);
    const replay = await reserve(sku, 4, key, tokenA, true);
    expect(replay.status).toBe(201);
    expect(replay.headers.get("Idempotency-Replayed")).toBe("true");
    expect(await replay.json()).toEqual(original);
    expect(await stock(sku)).toBe(10);
    expect(await counts(sku)).toEqual({ reservations: 1, keys: 1 });
  }, 30_000);

  test("server-derived clients cannot read or release each other's reservation; keys are client scoped", async () => {
    const sku = await fixture("ownership", 10);
    const key = `shared-client-key-${run}`;
    const reservationA = await (await reserve(sku, 2, key, tokenA)).json() as Reservation;
    for (const method of ["GET", "DELETE"]) {
      await expectError(await request(`/reservations/${reservationA.id}`, { method }, tokenB), 404, "not_found");
    }
    expect(await stock(sku)).toBe(8);
    const responseB = await reserve(sku, 3, key, tokenB, true);
    expect(responseB.status).toBe(201);
    const reservationB = await responseB.json() as Reservation;
    expect(reservationB.id).not.toBe(reservationA.id);
    expect(await stock(sku)).toBe(5);
    const owners = await admin`
      SELECT id, client_id FROM stock_reservation.reservations WHERE sku = ${sku}
    `;
    expect(owners.find((row: { id: string }) => row.id === reservationA.id).client_id).toBe(clientA);
    expect(owners.find((row: { id: string }) => row.id === reservationB.id).client_id).toBe(clientB);
  });

  test("failed stock requests retain no key and can succeed after stock is released", async () => {
    const sku = await fixture("retry-stock", 1);
    const held = await (await reserve(sku, 1)).json() as Reservation;
    const key = `retry-stock-${run}`;
    await expectError(await reserve(sku, 1, key), 409, "insufficient_inventory");
    expect(await counts(sku)).toEqual({ reservations: 1, keys: 1 });
    expect((await request(`/reservations/${held.id}`, { method: "DELETE" })).status).toBe(200);
    expect((await reserve(sku, 1, key, tokenA, true)).status).toBe(201);
    expect(await stock(sku)).toBe(0);
    expect(await counts(sku)).toEqual({ reservations: 2, keys: 2 });
  });

  test("unknown inventory and reservation IDs return bounded errors", async () => {
    const missing = `missing-${run}`;
    await expectError(await reserve(missing, 1), 404, "not_found");
    expect(await counts(missing)).toEqual({ reservations: 0, keys: 0 });
    for (const id of [crypto.randomUUID(), "not-a-uuid"]) {
      await expectError(await request(`/reservations/${id}`), 404, "not_found");
      await expectError(await request(`/reservations/${id}`, { method: "DELETE" }), 404, "not_found");
    }
  });

  test("malformed, invalid, and oversized bodies never mutate stock", async () => {
    const sku = await fixture("validation", 10);
    const invalidBodies = [
      null, [], {}, { sku }, { sku, quantity: 0 }, { sku, quantity: -1 },
      { sku, quantity: 1.5 }, { sku, quantity: "1" }, { sku, quantity: 1001 },
      { sku, quantity: 2_147_483_648 }, { sku: "", quantity: 1 },
      { sku: "x".repeat(65), quantity: 1 }, { sku: "x'; DROP TABLE inventory;--", quantity: 1 },
      { sku, quantity: 1, client_id: clientB },
    ];
    for (const body of invalidBodies) {
      await expectError(await request("/reservations", {
        method: "POST",
        headers: { "Content-Type": "application/json", "Idempotency-Key": crypto.randomUUID() },
        body: JSON.stringify(body),
      }), 400, "invalid_request");
    }
    await expectError(await request("/reservations", {
      method: "POST", headers: { "Content-Type": "application/json", "Idempotency-Key": crypto.randomUUID() },
      body: "{invalid JSON",
    }), 400, "invalid_json");
    const oversized = await request("/reservations", {
      method: "POST", headers: { "Content-Type": "application/json", "Idempotency-Key": crypto.randomUUID() },
      body: JSON.stringify({ sku, quantity: 1, padding: "x".repeat(8192) }),
    });
    expect(oversized.status).toBe(413);
    expect(await stock(sku)).toBe(10);
    expect(await counts(sku)).toEqual({ reservations: 0, keys: 0 });
  });

  test("missing, malformed, or oversized idempotency keys cannot reserve stock", async () => {
    const sku = await fixture("validation-key", 10);
    for (const key of [null, "bad key", "x".repeat(129)]) {
      const headers: Record<string, string> = { "Content-Type": "application/json" };
      if (key !== null) headers["Idempotency-Key"] = key;
      await expectError(await request("/reservations", {
        method: "POST", headers, body: JSON.stringify({ sku, quantity: 1 }),
      }), 400, "invalid_idempotency_key");
    }
    expect(await stock(sku)).toBe(10);
    expect(await counts(sku)).toEqual({ reservations: 0, keys: 0 });
  });

  test("an INSERT failure rolls back the inventory decrement and key, then permits a clean retry", async () => {
    const sku = await fixture("rollback", 10);
    const key = `rollback-${run}`;
    const errorsBefore = applicationErrors.length;
    // This named constraint intentionally prevents overlapping runs against the
    // same database. Never drop a pre-existing constraint before installing it.
    await admin.file(new URL("./fixtures/rollback-guard.sql", import.meta.url).pathname);
    try {
      const failed = await reserve(sku, 3, key);
      await expectError(failed, 503, "database_unavailable");
      expect(applicationErrors.length).toBe(errorsBefore + 1);
      expect(await stock(sku)).toBe(10);
      expect(await counts(sku)).toEqual({ reservations: 0, keys: 0 });
    } finally {
      await admin.file(new URL("./fixtures/remove-rollback-guard.sql", import.meta.url).pathname);
    }
    const retry = await reserve(sku, 3, key, tokenA, true);
    expect(retry.status).toBe(201);
    expect(await stock(sku)).toBe(7);
    expect(await counts(sku)).toEqual({ reservations: 1, keys: 1 });
  }, 30_000);

  test("a failed release rolls back its inventory increment and leaves the reservation active", async () => {
    const sku = await fixture("release-rollback", 10);
    const key = `release-rollback-${run}`;
    const created = await reserve(sku, 3, key);
    expect(created.status).toBe(201);
    const original = await created.json() as Reservation;
    expect(await stock(sku)).toBe(7);
    const errorsBefore = applicationErrors.length;
    await admin.file(new URL("./fixtures/release-rollback-guard.sql", import.meta.url).pathname);
    try {
      const failed = await request(`/reservations/${original.id}`, { method: "DELETE" });
      await expectError(failed, 503, "database_unavailable");
      expect(applicationErrors.length).toBe(errorsBefore + 1);
      expect(await stock(sku)).toBe(7);
      const current = await request(`/reservations/${original.id}`);
      expect(current.status).toBe(200);
      expect(await current.json()).toEqual(original);
      expect(await counts(sku)).toEqual({ reservations: 1, keys: 1 });
    } finally {
      await admin.file(new URL("./fixtures/remove-release-rollback-guard.sql", import.meta.url).pathname);
    }
    const retry = await request(`/reservations/${original.id}`, { method: "DELETE" }, tokenA, true);
    expect(retry.status).toBe(200);
    const released = await retry.json() as Reservation;
    expect(released.status).toBe("released");
    expect(released.released_at).not.toBeNull();
    expect(await stock(sku)).toBe(10);
    const replay = await reserve(sku, 3, key);
    expect(replay.status).toBe(201);
    expect(await replay.json()).toEqual(original);
    expect(await counts(sku)).toEqual({ reservations: 1, keys: 1 });
  }, 30_000);
});
