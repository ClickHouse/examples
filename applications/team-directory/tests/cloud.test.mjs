// Run only against a disposable, seeded Cloud fixture and the production server.
import test, { after } from "node:test";
import assert from "node:assert/strict";
import knex from "knex";
import { Client } from "pg";
import { checkServerIdentity } from "node:tls";
import { readFileSync } from "node:fs";
import { databaseConfig } from "../server/domain/database.mjs";
const base = process.env.BASE_URL || "http://127.0.0.1:3000";
const origin = new URL(base).origin;
const alex = "00000000-0000-4000-8000-000000000001";
const sam = "00000000-0000-4000-8000-000000000002";
const db = knex(databaseConfig());
const owner = knex(
  databaseConfig({
    ...process.env,
    PGUSER: process.env.TEST_OWNER_PGUSER,
    PGPASSWORD: process.env.TEST_OWNER_PGPASSWORD,
  }),
);
let cookie, samCookie;
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
async function request(path, options = {}, session = cookie) {
  const headers = {
    Origin: origin,
    ...(session ? { Cookie: session } : {}),
    ...(options.body ? { "Content-Type": "application/json" } : {}),
    ...options.headers,
  };
  return fetch(base + path, {
    ...options,
    headers,
    body: options.body ? JSON.stringify(options.body) : undefined,
  });
}
async function login(email) {
  const result = await request(
    "/api/auth/login",
    { method: "POST", body: { email, password: process.env.DEMO_PASSWORD } },
    null,
  );
  assert.equal(result.status, 200, await result.text());
  const value = result.headers
    .getSetCookie()
    .find((c) => c.startsWith("nuxt-session="));
  assert.ok(value);
  assert.ok(/HttpOnly/i.test(value));
  assert.ok(/SameSite=Lax/i.test(value));
  assert.ok(/Expires=/i.test(value), "Finite cookie expiry is required");
  const expiry = new Date(value.match(/Expires=([^;]+)/i)[1]).getTime();
  assert.ok(
    Math.abs(expiry - Date.now() - 7200000) < 10000,
    "Cookie expires in two hours",
  );
  assert.ok(!/; Secure/i.test(value)); // Explicit loopback-only override in the test environment.
  return value.split(";")[0];
}
async function profile(id = alex) {
  const r = await request("/api/profiles/" + id);
  assert.equal(r.status, 200);
  return r.json();
}
function edit(p, patch = {}) {
  return {
    revision: p.revision,
    displayName: p.display_name,
    biography: p.biography,
    location: p.location,
    skillIds: p.skills.map((s) => s.id),
    ...patch,
  };
}
after(async () => {
  await db.destroy();
  await owner.destroy();
});
test("sealed sign-in, session fetch, logout clearing and honest prior-cookie replay", async () => {
  cookie = await login("alex@example.test");
  samCookie = await login("sam@example.test");
  const session = await request("/api/_auth/session");
  assert.equal(session.status, 200);
  assert.equal((await session.json()).user.id, alex);
  const out = await request("/api/_auth/session", { method: "DELETE" });
  assert.equal(out.status, 200);
  assert.ok(out.headers.get("set-cookie").startsWith("nuxt-session=;"));
  assert.equal((await request("/api/directory", {}, null)).status, 401);
  assert.equal((await request("/api/directory")).status, 200); // Sealed cookie is not server-revoked.
  assert.equal(
    (await request("/api/directory", {}, cookie.slice(0, -1) + "!")).status,
    401,
  );
});
test("server-owned identity blocks foreign writes and injected owner fields", async () => {
  const before = await profile(sam);
  assert.equal(
    (
      await request("/api/profiles/" + sam, {
        method: "PUT",
        body: edit(before, { displayName: "Forged" }),
      })
    ).status,
    404,
  );
  const mine = await profile();
  assert.equal(
    (
      await request("/api/profiles/" + alex, {
        method: "PUT",
        body: { ...edit(mine), ownerId: sam },
      })
    ).status,
    422,
  );
  assert.deepEqual(await profile(sam), before);
  assert.equal((await request("/api/profiles/" + "-".repeat(36))).status, 404);
  const upper = await request("/api/profiles/" + alex.toUpperCase(), {
    method: "PUT",
    body: edit(mine, { displayName: "Alex Cloud" }),
  });
  assert.equal(upper.status, 200);
});
test("profile plus skills is atomic, including rollback after earlier writes", async () => {
  const before = await profile();
  assert.equal(
    (
      await request("/api/profiles/" + alex, {
        method: "PUT",
        body: edit(before, {
          displayName: "Must roll back",
          skillIds: [999999],
        }),
      })
    ).status,
    422,
  );
  assert.deepEqual(await profile(), before);
  assert.equal(
    (
      await request("/api/profiles/" + alex, {
        method: "PUT",
        body: edit(before, { skillIds: [2, 2] }),
      })
    ).status,
    422,
  );
  const r = await request("/api/profiles/" + alex, {
    method: "PUT",
    body: edit(before, {
      biography: "Writes durable profiles",
      skillIds: [1, 2, 3],
    }),
  });
  assert.equal(r.status, 200);
  const changed = await r.json();
  assert.equal(changed.revision, before.revision + 1);
  assert.deepEqual(changed.skills.map((s) => s.id).sort(), [1, 2, 3]);
});
test("two HTTP editors actually wait on a held row lock; exactly one revision wins", async () => {
  const before = await profile();
  const holder = await db.transaction();
  await holder("users").where("id", alex).forUpdate().first();
  const writes = ["First editor", "Second editor"].map((displayName) =>
    request("/api/profiles/" + alex, {
      method: "PUT",
      body: edit(before, { displayName }),
    }),
  );
  let observed = 0;
  try {
    for (let i = 0; i < 100; i++) {
      const result = await db.raw(
        "SELECT count(*)::int AS n FROM pg_stat_activity WHERE usename=current_user AND wait_event_type='Lock' AND query ILIKE '%users%' AND pid<>pg_backend_pid()",
      );
      observed = result.rows[0].n;
      if (observed >= 2) break;
      await sleep(100);
    }
    assert.ok(
      observed >= 2,
      `Only ${observed} blocked independent requests observed`,
    );
  } finally {
    await holder.commit();
  }
  const results = await Promise.all(writes);
  assert.deepEqual(results.map((r) => r.status).sort(), [200, 409]);
  assert.equal((await profile()).revision, before.revision + 1);
  console.log(
    "Observed two independent HTTP transactions waiting on the parent-row lock.",
  );
});
test("deterministic bounded directory pages and literal wildcard search", async () => {
  const first = await (await request("/api/directory")).json();
  const second = await (await request("/api/directory?page=2")).json();
  assert.equal(first.profiles.length, 12);
  assert.equal(second.profiles.length, 4);
  assert.equal(first.total, 16);
  assert.equal(
    new Set([...first.profiles, ...second.profiles].map((p) => p.id)).size,
    16,
  );
  assert.deepEqual(
    (await (await request("/api/directory")).json()).profiles.map((p) => p.id),
    first.profiles.map((p) => p.id),
  );
  for (const q of ["%", "_", "\\"])
    assert.equal(
      (
        await (
          await request("/api/directory?q=" + encodeURIComponent(q))
        ).json()
      ).total,
      0,
    );
  const selected = await (
    await request("/api/directory?skill=6&location=Berlin")
  ).json();
  assert.ok(selected.profiles.some((p) => p.id === sam));
  assert.ok(selected.profiles.every((p) => p.skills.some((s) => s.id === 6)));
  assert.equal((await request("/api/directory?page=1001")).status, 422);
  assert.equal((await request("/api/directory?sort=email")).status, 422);
});
test("origin, JSON body limit and native logout mutation are enforced server-side", async () => {
  const mine = await profile();
  for (const headers of [
    { Origin: "" },
    { Origin: "https://foreign.example" },
    { Origin: origin, "Sec-Fetch-Site": "cross-site" },
  ]) {
    assert.equal(
      (
        await request("/api/profiles/" + alex, {
          method: "PUT",
          body: edit(mine),
          headers,
        })
      ).status,
      403,
    );
    assert.equal(
      (await request("/api/_auth/session", { method: "DELETE", headers }))
        .status,
      403,
    );
  }
  assert.equal(
    (
      await request("/api/profiles/" + alex, {
        method: "PUT",
        body: edit(mine, { biography: "x".repeat(9000) }),
      })
    ).status,
    413,
  );
  const chunks = new ReadableStream({
    start(c) {
      c.enqueue(new TextEncoder().encode('{"x":"' + "x".repeat(9000) + '"}'));
      c.close();
    },
  });
  const large = await fetch(base + "/api/auth/login", {
    method: "POST",
    headers: { Origin: origin, "Content-Type": "application/json" },
    body: chunks,
    duplex: "half",
  });
  assert.equal(large.status, 413);
  assert.deepEqual(await profile(), mine);
});
test("account state is rechecked even when an earlier sealed cookie is replayed", async () => {
  await owner("users").where("id", alex).update("active", false);
  try {
    assert.equal((await request("/api/_auth/session")).status, 401);
    assert.equal((await request("/api/directory")).status, 401);
  } finally {
    await owner("users").where("id", alex).update("active", true);
  }
  assert.equal((await request("/api/directory")).status, 200);
});
test("runtime permissions and database membership keys/quota reject direct misuse", async () => {
  for (const [sql, code] of [
    ["CREATE TABLE directory.forbidden (id integer)", "42501"],
    ["UPDATE users SET email='changed@example.test' WHERE id=?", "42501"],
    ["UPDATE skills SET name='Uncontrolled' WHERE id=1", "42501"],
  ]) {
    await assert.rejects(
      () => db.raw(sql, sql.includes("?") ? [alex] : []),
      (e) => e.code === code,
    );
  }
  const trx = await db.transaction();
  try {
    await trx("user_skills").where("user_id", sam).delete();
    await trx("user_skills").insert(
      [1, 2, 3, 4, 5, 6].map((skill_id) => ({ user_id: sam, skill_id })),
    );
    await assert.rejects(
      () => trx("user_skills").insert({ user_id: sam, skill_id: 7 }),
      (e) => e.code === "23514",
    );
  } finally {
    await trx.rollback();
  }
  await assert.rejects(
    () => db("user_skills").insert({ user_id: sam, skill_id: 6 }),
    (e) => e.code === "23505",
  );
  await assert.rejects(
    () => db("user_skills").insert({ user_id: sam, skill_id: 99999 }),
    (e) => e.code === "23503",
  );
});
test("actual node-postgres TLS rejects the wrong CA and wrong certificate hostname", async () => {
  const config = databaseConfig().connection;
  for (const [name, ssl, pattern] of [
    [
      "CA",
      { ...config.ssl, ca: readFileSync(process.env.WRONG_CA_PATH, "utf8") },
      /certificate|self.signed|issuer/i,
    ],
    [
      "hostname",
      {
        ...config.ssl,
        checkServerIdentity: (_hostname, cert) =>
          checkServerIdentity("wrong-hostname.invalid", cert),
      },
      /hostname|altname|altnames|not cert/i,
    ],
  ]) {
    const client = new Client({ ...config, ssl });
    try {
      await assert.rejects(
        () => client.connect(),
        (e) => pattern.test(e.message),
      );
      console.log(`Verified ${name}-specific TLS rejection`);
    } finally {
      await client.end().catch(() => {});
    }
  }
  const version = await db.raw("SHOW server_version");
  console.log("Postgres version:", version.rows[0].server_version);
});
test("sign-in limiter remains enabled and returns a bounded retry response", async () => {
  const codes = [];
  for (let i = 0; i < 13; i++)
    codes.push(
      (
        await request(
          "/api/auth/login",
          {
            method: "POST",
            body: { email: "unknown@example.test", password: "not-correct" },
          },
          null,
        )
      ).status,
    );
  assert.ok(codes.includes(401));
  assert.equal(codes.at(-1), 429);
});
