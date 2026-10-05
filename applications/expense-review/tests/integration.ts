import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import pg from "pg";
import { createTRPCClient, httpLink } from "@trpc/client";
import type { AppRouter } from "../src/server/router";
import { connection } from "../src/server/db";
const origin = process.env.APP_ORIGIN ?? "http://127.0.0.1:4332";
const client = createTRPCClient<AppRouter>({
  links: [
    httpLink({
      url: origin + "/api/trpc",
      headers: { Origin: origin, "X-Expense-Review": "1" },
    }),
  ],
});
const owner = new pg.Pool(
    connection({
      user: process.env.DB_OWNER_USER,
      password: process.env.DB_OWNER_PASSWORD,
    }),
  ),
  runtime = new pg.Pool(connection());
const ids = [900000001, 900000002];
let server: ReturnType<typeof spawn>;
async function start() {
  server = spawn(
    process.execPath,
    [
      "node_modules/next/dist/bin/next",
      "start",
      "--hostname",
      "127.0.0.1",
      "--port",
      "4332",
    ],
    { env: process.env, stdio: ["ignore", "pipe", "pipe"] },
  );
  await new Promise<void>((resolve, reject) => {
    server.stdout!.on("data", (chunk) => {
      if (String(chunk).includes("Ready")) resolve();
    });
    server.once("exit", (code) => reject(new Error("Server exited " + code)));
  });
}
async function stop() {
  await new Promise<void>((resolve) => {
    server.once("exit", () => resolve());
    server.kill("SIGTERM");
  });
}
async function cleanup() {
  await owner.query("DELETE FROM decisions WHERE claim_id=ANY($1)", [ids]);
  await owner.query("DELETE FROM line_items WHERE claim_id=ANY($1)", [ids]);
  await owner.query("DELETE FROM claims WHERE id=ANY($1)", [ids]);
}
const conflict = (e: unknown) =>
  (e as { data?: { code?: string } }).data?.code === "CONFLICT";
try {
  await cleanup();
  await owner.query(
    "INSERT INTO claims(id,employee,category,submitted_at,memo) VALUES($1,'Integration reviewer','Travel',CURRENT_TIMESTAMP,'Original reviewed memo'),($2,'Integration reviewer','Meals',CURRENT_TIMESTAMP,'Second fixture claim')",
    ids,
  );
  await owner.query(
    "INSERT INTO line_items(claim_id,position,description,amount_cents) VALUES($1,0,'Rail journey',2500),($1,1,'Local bus',500),($2,0,'Team meal',1200)",
    ids,
  );
  await start();
  const list = await client.list.query();
  assert.equal(list.totalCount, list.claims.length);
  assert.ok(list.claims.length >= 502);
  let original = await client.detail.query({ id: ids[0]! });
  assert.equal(original.totalCents, 3000);
  const edited = await client.edit.mutate({
    id: original.id,
    revision: original.revision,
    memo: "Amended reviewed memo",
    lines: [
      { description: "Rail journey", amountCents: 2800 },
      { description: "Local bus", amountCents: 500 },
    ],
  });
  assert.equal(edited.revision, 1);
  assert.equal(edited.totalCents, 3300);
  await assert.rejects(
    client.decide.mutate({
      id: original.id,
      revision: original.revision,
      decision: "approved",
      reason: "Checked original receipts",
    }),
    conflict,
  );
  const decisions = await Promise.allSettled([
    client.decide.mutate({
      id: edited.id,
      revision: edited.revision,
      decision: "approved",
      reason: "Checked amended receipts",
    }),
    client.decide.mutate({
      id: edited.id,
      revision: edited.revision,
      decision: "rejected",
      reason: "Duplicate review attempt",
    }),
  ]);
  assert.equal(decisions.filter((r) => r.status === "fulfilled").length, 1);
  assert.equal(
    decisions.filter((r) => r.status === "rejected" && conflict(r.reason))
      .length,
    1,
  );
  let saved = await client.detail.query({ id: original.id });
  assert.equal(saved.history.length, 1);
  assert.equal(saved.history[0]!.reviewedRevision, 1);
  assert.equal(saved.history[0]!.totalCents, 3300);
  assert.equal(saved.history[0]!.memoSnapshot, "Amended reviewed memo");
  assert.deepEqual(saved.history[0]!.snapshot, edited.lines);
  const amendment = await client.edit.mutate({
    id: saved.id,
    revision: saved.revision,
    memo: "New pending amendment",
    lines: [{ description: "Revised expense", amountCents: 4500 }],
  });
  assert.equal(amendment.status, "pending");
  assert.equal(amendment.history[0]!.totalCents, 3300);
  assert.equal(amendment.history[0]!.memoSnapshot, "Amended reviewed memo");
  await stop();
  await start();
  saved = await client.detail.query({ id: original.id });
  assert.equal(saved.totalCents, 4500);
  assert.equal(saved.history.length, 1);
  console.log(
    "Typed edit/decision path, exact revision concurrency, stored memo/line snapshots and genuine restart passed",
  );
  const second = await client.detail.query({ id: ids[1]! });
  await owner.query(
    `CREATE FUNCTION fixture_fail_history() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.claim_id=900000002 THEN RAISE EXCEPTION 'controlled fixture history failure'; END IF; RETURN NEW; END $$`,
  );
  await owner.query(
    "CREATE TRIGGER fixture_fail_history BEFORE INSERT ON decisions FOR EACH ROW EXECUTE FUNCTION fixture_fail_history()",
  );
  await assert.rejects(
    client.decide.mutate({
      id: second.id,
      revision: second.revision,
      decision: "approved",
      reason: "Controlled rollback test",
    }),
  );
  const rolledBack = await client.detail.query({ id: second.id });
  assert.equal(rolledBack.status, "pending");
  assert.equal(rolledBack.revision, 0);
  assert.equal(rolledBack.history.length, 0);
  await owner.query("DROP TRIGGER fixture_fail_history ON decisions");
  await owner.query("DROP FUNCTION fixture_fail_history()");
  console.log("History insert failure rolls back decision/status/revision");
  for (const sql of [
    "UPDATE decisions SET reason=reason",
    "DELETE FROM decisions",
    "DELETE FROM claims WHERE id=900000002",
    "CREATE TABLE unauthorized(id integer)",
  ])
    await assert.rejects(
      runtime.query(sql),
      (e) => (e as { code?: string }).code === "42501",
    );
  for (const lines of [
    [{ description: "Bad fractional money", amountCents: 1.5 }],
    [{ description: "Bad negative money", amountCents: -1 }],
    [],
  ])
    await assert.rejects(
      client.edit.mutate({
        id: saved.id,
        revision: saved.revision,
        memo: "Invalid money fixture",
        lines,
      }),
      (e) => (e as { data?: { code?: string } }).data?.code === "BAD_REQUEST",
    );
  await assert.rejects(
    client.detail.query({ id: 2147483648 }),
    (e) => (e as { data?: { code?: string } }).data?.code === "BAD_REQUEST",
  );
  console.log(
    "Integer minor units, invalid input, complete dataset and runtime append-only history grants passed",
  );
} finally {
  if (server! && server.exitCode === null) await stop();
  await owner.query("DROP TRIGGER IF EXISTS fixture_fail_history ON decisions");
  await owner.query("DROP FUNCTION IF EXISTS fixture_fail_history()");
  await cleanup();
  await owner.end();
  await runtime.end();
}
