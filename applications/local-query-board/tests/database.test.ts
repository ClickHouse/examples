import { test, expect, afterAll } from "bun:test";
import { eq, sql } from "drizzle-orm";
import { connectDatabase, database } from "../src/server/database";
import { tasks } from "../src/server/schema";
import { createTask, updateTask } from "../src/server/writes";
const pool = await connectDatabase();
const db = database(pool);
afterAll(() => pool.end());
test("same-transaction IDs, concurrent revisions, invalid writes and runtime grants", async () => {
  const created = await createTask(db, {
    title: "Integration " + crypto.randomUUID(),
    project_id: "10000000-0000-4000-8000-000000000001",
    priority: "medium",
  });
  expect(Number.isInteger(created.txid)).toBe(true);
  const attempts = await Promise.allSettled(
    Array.from({ length: 8 }, () =>
      updateTask(db, created.task.id, {
        revision: 1,
        status: "doing",
        priority: "high",
      }),
    ),
  );
  expect(attempts.filter((x) => x.status === "fulfilled")).toHaveLength(1);
  expect(attempts.filter((x) => x.status === "rejected")).toHaveLength(7);
  const [saved] = await db
    .select()
    .from(tasks)
    .where(eq(tasks.id, created.task.id));
  expect(saved!.revision).toBe(2);
  expect(saved!.status).toBe("doing");
  await expect(
    createTask(db, {
      title: "Hidden",
      project_id: "10000000-0000-4000-8000-000000000099",
      priority: "medium",
    }),
  ).rejects.toThrow();
  await expect(
    updateTask(db, created.task.id, {
      revision: 2,
      status: "invented",
      priority: "high",
    }),
  ).rejects.toThrow();
  const [after] = await db
    .select()
    .from(tasks)
    .where(eq(tasks.id, created.task.id));
  expect(after).toEqual(saved);
  await expect(
    Promise.resolve(db.execute(sql`CREATE TABLE planning.forbidden(id int)`)),
  ).rejects.toThrow();
  await expect(
    Promise.resolve(
      db.execute(sql`DELETE FROM planning.tasks WHERE id=${created.task.id}`),
    ),
  ).rejects.toThrow();
});
