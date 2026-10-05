import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import pg from "pg";
import { initClient } from "@ts-rest/core";
import { contract, type Appointment } from "../shared/contract.js";
import { createPool, connection } from "../server/db.js";
import { bounds } from "../server/appointments.js";
const origin = process.env.APP_ORIGIN ?? "http://127.0.0.1:4331";
const owner = new pg.Pool({
  ...connection(),
  user: process.env.DB_OWNER_USER,
  password: process.env.DB_OWNER_PASSWORD,
});
const runtime = createPool();
const client = initClient(contract, {
  baseUrl: origin,
  baseHeaders: { Origin: origin, "X-Workshop-Calendar": "1" },
});
const ids = [800000001, 800000002, 800000003];
const date = "2030-02-04";
let server: ReturnType<typeof spawn>;
async function start() {
  server = spawn(process.execPath, ["build/server/server.js"], {
    env: process.env,
    stdio: ["ignore", "pipe", "pipe"],
  });
  await new Promise<void>((resolve, reject) => {
    server.stdout!.once("data", () => resolve());
    server.once("exit", (code) => reject(new Error("Server exited " + code)));
  });
}
async function stop() {
  await new Promise<void>((resolve) => {
    server.once("exit", () => resolve());
    server.kill("SIGTERM");
  });
}
const body = (a: Appointment, startsAt: string) => ({
  revision: a.revision,
  bayId: a.bayId,
  serviceId: a.serviceId,
  customer: a.customer,
  note: a.note,
  startsAt,
});
async function day() {
  const r = await client.day({ query: { date } });
  assert.equal(r.status, 200);
  if (r.status !== 200) throw new Error("read failed");
  return r.body;
}
try {
  await owner.query("DELETE FROM appointments WHERE id=ANY($1)", [ids]);
  await owner.query(
    `INSERT INTO appointments (id,bay_id,service_id,customer,note,starts_at,ends_at,duration_minutes) VALUES
    ($1,1,1,'Integration one','','2030-02-04T09:00:00Z','2030-02-04T09:30:00Z',30),
    ($2,1,1,'Integration two','','2030-02-04T10:00:00Z','2030-02-04T10:30:00Z',30),
    ($3,2,1,'Integration three','','2030-02-04T09:00:00Z','2030-02-04T09:30:00Z',30)`,
    ids,
  );
  await start();
  const initial = await day();
  assert.deepEqual(
    initial.utilization.map((b) => b.bookedMinutes),
    [60, 30, 0],
  );
  const a = initial.appointments.find((a) => a.id === ids[0])!,
    b = initial.appointments.find((a) => a.id === ids[1])!;
  const race = await Promise.all([
    client.update({
      params: { id: String(a.id) },
      body: body(a, "2030-02-04T11:00:00Z"),
    }),
    client.update({
      params: { id: String(b.id) },
      body: body(b, "2030-02-04T11:00:00Z"),
    }),
  ]);
  assert.deepEqual(race.map((r) => r.status).sort(), [200, 409]);
  console.log("Concurrent same-bay overlap: one commit, one409");
  const current = await day();
  const moved = current.appointments.find(
    (a) => a.startsAt === "2030-02-04T11:00:00.000Z",
  )!;
  assert.equal(
    (
      await client.update({
        params: { id: String(moved.id) },
        body: body(moved, "2030-02-04T11:30:00Z"),
      })
    ).status,
    200,
  );
  assert.equal(
    (
      await client.update({
        params: { id: String(moved.id) },
        body: body(moved, "2030-02-04T12:00:00Z"),
      })
    ).status,
    409,
  );
  await stop();
  await start();
  assert.equal(
    (await day()).appointments.find((a) => a.id === moved.id)!.startsAt,
    "2030-02-04T11:30:00.000Z",
  );
  console.log("Successful reschedule survives genuine server restart");
  const saved = (await day()).appointments.find((a) => a.id === moved.id)!;
  for (const timestamp of [
    "2030-02-04T08:00:00Z",
    "2030-02-04T17:00:00Z",
    "2030-02-04T12:01:00Z",
    "2030-02-04T12:00:00.000001Z",
  ])
    assert.equal(
      (
        await client.update({
          params: { id: String(saved.id) },
          body: body(saved, timestamp),
        })
      ).status,
      400,
    );
  const raw = await fetch(origin + "/api/appointments/" + saved.id, {
    method: "PUT",
    headers: {
      Origin: origin,
      "X-Workshop-Calendar": "1",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      ...body(saved, "2030-02-04T12:00:00Z"),
      endsAt: "2030-02-04T15:00:00Z",
    }),
  });
  assert.equal(raw.status, 400);
  assert.equal(
    (await client.day({ query: { date: "2030-02-31" } })).status,
    400,
  );
  for (const sql of [
    "UPDATE services SET name='changed' WHERE id=1",
    "DELETE FROM appointments WHERE id=800000003",
    "CREATE TABLE unauthorized (id integer)",
  ])
    await assert.rejects(
      runtime.query(sql),
      (e) => (e as { code?: string }).code === "42501",
    );
  const occupied = (await day()).appointments.find(
    (a) => a.bayId === 1 && a.id !== saved.id,
  )!;
  await assert.rejects(
    runtime.query(
      "UPDATE appointments SET starts_at=$1,ends_at=$2 WHERE id=$3",
      [occupied.startsAt, occupied.endsAt, saved.id],
    ),
    (e) => (e as { code?: string }).code === "23P01",
  );
  assert.equal(
    (new Date(bounds("2030-03-31")[1]!).valueOf() -
      new Date(bounds("2030-03-31")[0]!).valueOf()) /
      3600000,
    23,
  );
  console.log(
    "Invalid input, stale revision, database overlap, restricted grants, stored totals and DST boundaries passed",
  );
} finally {
  if (server! && server.exitCode === null) await stop();
  await owner.query("DELETE FROM appointments WHERE id=ANY($1)", [ids]);
  await owner.end();
  await runtime.end();
}
