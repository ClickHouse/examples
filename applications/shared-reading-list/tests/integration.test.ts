import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { db, client } from "../src/lib/server/db";
import { user } from "../src/lib/server/schema";
import { eq } from "drizzle-orm";
import {
  createLink,
  getLink,
  listLinks,
  updateLink,
} from "../src/lib/server/library";
const base = process.env.TEST_BASE_URL ?? "http://localhost:3000";
const suffix = crypto.randomUUID();
let a, b, id;
async function signup(label) {
  const res = await fetch(`${base}/api/auth/sign-up/email`, {
    method: "POST",
    headers: { "content-type": "application/json", origin: base },
    body: JSON.stringify({
      name: `Test ${label}`,
      email: `${label}-${suffix}@example.invalid`,
      password: `Strong-test-${suffix}`,
    }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();
  return {
    id: body.user.id,
    cookie: res.headers
      .getSetCookie()
      .map((c) => c.split(";")[0])
      .join("; "),
  };
}
async function form(path, who, values, origin = base) {
  return fetch(base + path, {
    method: "POST",
    redirect: "manual",
    headers: {
      accept: "text/html",
      cookie: who?.cookie ?? "",
      origin,
      "content-type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams(values),
  });
}
before(async () => {
  a = await signup("alice");
  b = await signup("bob");
});
after(async () => {
  for (const account of [a, b])
    if (account) await db.delete(user).where(eq(user.id, account.id));
  await client.end();
});
test("signed-out reads redirect; writes require identity; cross-origin forms rejected", async () => {
  assert.equal((await fetch(base + "/", { redirect: "manual" })).status, 303);
  const signedOut = await form("/?/save", null, {
    title: "test",
    url: "https://example.com",
    notes: "",
    tags: "",
  });
  assert.equal(signedOut.status, 303);
  assert.equal(signedOut.headers.get("location"), "/sign-in");
  assert.equal(
    (
      await form(
        "/?/save",
        a,
        { title: "test", url: "https://example.com", notes: "", tags: "" },
        "https://evil.example",
      )
    ).status,
    403,
  );
});
test("HTTP save persists normalized tags and invalid input is rejected", async () => {
  assert.equal(
    (
      await form("/?/save", a, {
        title: "bad",
        url: "javascript:alert(1)",
        notes: "",
        tags: "",
      })
    ).status,
    400,
  );
  const res = await form("/?/save", a, {
    title: `Transactions ${suffix}`,
    url: `https://example.com/${suffix}`,
    notes: "Durable PostgreSQL notes",
    tags: "Postgres, transactions, postgres",
  });
  assert.equal(res.status, 303);
  id = res.headers.get("location").split("/").at(-1);
  assert.equal((await getLink(id)).ownerId, a.id);
  assert.deepEqual((await getLink(id)).tags, ["postgres", "transactions"]);
  assert.equal(
    (
      await form("/?/save", a, {
        title: "duplicate",
        url: `https://example.com/${suffix}`,
        notes: "",
        tags: "",
      })
    ).status,
    409,
  );
});
test("another user cannot edit or delete; identity is not accepted from form input", async () => {
  for (const action of ["update", "delete"])
    assert.equal(
      (
        await form(`/links/${id}?/${action}`, b, {
          title: "Taken over",
          url: "https://example.com/hijack",
          notes: "",
          tags: "",
          version: "1",
          ownerId: a.id,
        })
      ).status,
      409,
    );
  assert.equal((await getLink(id)).title, `Transactions ${suffix}`);
  const html = await (
    await fetch(`${base}/links/${id}`, { headers: { cookie: b.cookie } })
  ).text();
  assert.ok(!html.includes("Edit your link"));
});
test("competing edits accept one version, search and tag filters reflect edits", async () => {
  const values = {
    title: "Indexing concurrency",
    url: `https://example.com/${suffix}`,
    notes: "Version checked updates",
    tags: ["indexing"],
  };
  const outcomes = await Promise.all([
    updateLink(id, a.id, 1, values),
    updateLink(id, a.id, 1, { ...values, title: "Concurrent indexing" }),
  ]);
  assert.equal(outcomes.filter(Boolean).length, 1);
  assert.equal((await getLink(id)).version, 2);
  assert.ok(
    (await listLinks("indexing", "indexing")).some((row) => row.id === id),
  );
  assert.ok(
    !(await listLinks("transactions", "postgres")).some((row) => row.id === id),
  );
  const response = await fetch(`${base}/?q=indexing&tag=indexing`, {
    headers: { cookie: b.cookie },
  });
  assert.equal(response.status, 200);
  assert.ok((await response.text()).includes("indexing"));
});
test("durable session rows, restricted role and owner delete", async () => {
  assert.equal(
    (
      await fetch(base + "/api/auth/get-session", {
        headers: { cookie: a.cookie },
      })
    ).status,
    200,
  );
  const sessions =
    await client`SELECT count(*)::int AS count FROM reading.session WHERE user_id=${a.id}`;
  assert.equal(sessions[0].count, 1);
  await assert.rejects(
    client`CREATE TABLE reading.forbidden (id integer)`,
    (e) => (e as { code: string }).code === "42501",
  );
  await assert.rejects(
    client`SELECT * FROM reading_migrations.__drizzle_migrations`,
    (e) => (e as { code: string }).code === "42501",
  );
  assert.equal(
    (await form(`/links/${id}?/delete`, a, { version: "2" })).status,
    303,
  );
  assert.equal(await getLink(id), undefined);
  const logout = await form("/sign-out", a, {});
  assert.equal(logout.status, 303);
  const expired = await (
    await fetch(base + "/api/auth/get-session", {
      headers: { cookie: a.cookie },
    })
  ).json();
  assert.equal(expired, null);
});
