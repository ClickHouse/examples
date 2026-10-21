import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";
import { and, count, eq } from "drizzle-orm";
import { createDb } from "../../src/db";
import { addDays, appTimeZone, todayIn } from "../../src/lib/dates";
import {
  archiveHabit,
  createHabit,
  DEMO_USER_ID,
  habitHistory,
  listHabits,
  setCheckIn,
  streaks,
} from "../../src/lib/habits";
import { checkIns, habits } from "../../src/schema";

// Runs as the app role against DATABASE_URL (and PGSSLROOTCERT for managed
// Postgres). It creates habits named "test-..." and archives them afterwards.
if (!process.env.DATABASE_URL)
  throw new Error("Set DATABASE_URL to run integration tests.");

const db = createDb();
const today = todayIn(appTimeZone());
const created: number[] = [];

async function newHabit() {
  const id = await createHabit(
    db,
    DEMO_USER_ID,
    `test-${randomUUID().slice(0, 8)}`,
  );
  created.push(id);
  return id;
}

const rowsFor = async (habitId: number, day: string) =>
  (
    await db
      .select({ n: count() })
      .from(checkIns)
      .where(and(eq(checkIns.habitId, habitId), eq(checkIns.day, day)))
  )[0].n;

test.after(async () => {
  for (const id of created) {
    await db.delete(checkIns).where(eq(checkIns.habitId, id));
    await archiveHabit(db, DEMO_USER_ID, id);
  }
  await db.$client.end();
});

test("20 concurrent check-ins for the same day leave exactly one row", async () => {
  const id = await newHabit();
  await Promise.all(
    Array.from({ length: 20 }, () =>
      setCheckIn(db, DEMO_USER_ID, id, today, true),
    ),
  );
  assert.equal(await rowsFor(id, today), 1);
});

test("the database rejects a duplicate even without ON CONFLICT", async () => {
  const id = await newHabit();
  await db.insert(checkIns).values({ habitId: id, day: today });
  await assert.rejects(
    db.insert(checkIns).values({ habitId: id, day: today }),
    (err: { cause?: { code?: string } }) => {
      assert.equal(err.cause?.code, "23505"); // unique_violation on (habit_id, day)
      return true;
    },
  );
});

test("unchecking is idempotent too", async () => {
  const id = await newHabit();
  await setCheckIn(db, DEMO_USER_ID, id, today, true);
  await Promise.all(
    Array.from({ length: 5 }, () =>
      setCheckIn(db, DEMO_USER_ID, id, today, false),
    ),
  );
  assert.equal(await rowsFor(id, today), 0);
});

test("streaks are computed in SQL with gaps and islands", async () => {
  const id = await newHabit();
  // A 3-day run ending today, after a gap, and an older 4-day run.
  for (const offset of [0, -1, -2, -5, -6, -7, -8]) {
    await setCheckIn(db, DEMO_USER_ID, id, addDays(today, offset), true);
  }
  assert.deepEqual((await streaks(db, DEMO_USER_ID, today)).get(id), {
    current: 3,
    longest: 4,
  });
  // A streak that ended yesterday is still current; one that ended two days ago is not.
  assert.equal(
    (await streaks(db, DEMO_USER_ID, addDays(today, 1))).get(id)?.current,
    3,
  );
  assert.equal(
    (await streaks(db, DEMO_USER_ID, addDays(today, 2))).get(id)?.current,
    0,
  );
});

test("list, history and archive", async () => {
  const id = await newHabit();
  await setCheckIn(db, DEMO_USER_ID, id, today, true);
  const listed = (
    await listHabits(db, DEMO_USER_ID, today, addDays(today, -6))
  ).find((h) => h.id === id);
  assert.ok(listed?.days.has(today));
  const history = await habitHistory(db, DEMO_USER_ID, id, today, 91);
  assert.equal(history?.days.length, 91);
  assert.deepEqual(history?.days.at(-1), { day: today, done: true });

  await archiveHabit(db, DEMO_USER_ID, id);
  assert.equal(await habitHistory(db, DEMO_USER_ID, id, today, 91), null);
  await setCheckIn(db, DEMO_USER_ID, id, addDays(today, -1), true); // archived: no-op
  assert.equal(await rowsFor(id, addDays(today, -1)), 0);
});

test("another user's habit cannot be checked in", async () => {
  const id = await newHabit();
  await setCheckIn(db, DEMO_USER_ID + 999, id, today, true);
  assert.equal(await rowsFor(id, today), 0);
});

test("the app role cannot run DDL", async () => {
  await assert.rejects(
    db.execute("create table habit_tracker.not_allowed (id int)"),
    (err: { cause?: { code?: string } }) => {
      assert.equal(err.cause?.code, "42501"); // insufficient_privilege
      return true;
    },
  );
  await assert.rejects(
    db.update(habits).set({ name: "renamed" }).where(eq(habits.id, created[0])),
  );
});

test(
  "managed Postgres connections use verified TLS",
  { skip: !process.env.PGSSLROOTCERT && "local Postgres has no TLS" },
  async () => {
    const { rows } = await db.execute<{ ssl: boolean }>(
      "select ssl from pg_stat_ssl where pid = pg_backend_pid()",
    );
    assert.equal(rows[0].ssl, true);
  },
);
