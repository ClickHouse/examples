import { and, eq, sql } from "drizzle-orm";
import type { Database } from "./database";
import { projects, tasks } from "./schema";
import { createTaskSchema, updateTaskSchema } from "../shared";
export class WriteError extends Error {
  constructor(
    public status: 400 | 404 | 409,
    message: string,
  ) {
    super(message);
  }
}
export async function createTask(db: Database, input: unknown) {
  const body = createTaskSchema.safeParse(input);
  if (!body.success)
    throw new WriteError(400, "A title, project and priority are required.");
  return db.transaction(async (tx) => {
    const [project] = await tx
      .select()
      .from(projects)
      .where(
        and(
          eq(projects.id, body.data.project_id),
          eq(projects.board_id, "studio"),
        ),
      );
    if (!project) throw new WriteError(400, "Choose a project on this board.");
    const [task] = await tx
      .insert(tasks)
      .values({
        id: crypto.randomUUID(),
        board_id: "studio",
        project_id: project.id,
        title: body.data.title,
        status: "todo",
        priority: body.data.priority,
        revision: 1,
      })
      .returning();
    const xid = await tx.execute<{ txid: string }>(
      sql`SELECT pg_current_xact_id()::xid::text AS txid`,
    );
    return { task, txid: Number(xid.rows[0]!.txid) };
  });
}
export async function updateTask(db: Database, id: string, input: unknown) {
  const body = updateTaskSchema.safeParse(input);
  if (!body.success)
    throw new WriteError(400, "Choose a valid status, priority and revision.");
  return db.transaction(async (tx) => {
    const [task] = await tx
      .update(tasks)
      .set({
        status: body.data.status,
        priority: body.data.priority,
        revision: sql`${tasks.revision}+1`,
      })
      .where(
        and(
          eq(tasks.id, id),
          eq(tasks.board_id, "studio"),
          eq(tasks.revision, body.data.revision),
        ),
      )
      .returning();
    if (!task)
      throw new WriteError(
        409,
        "This task changed. Review its latest version and try again.",
      );
    const xid = await tx.execute<{ txid: string }>(
      sql`SELECT pg_current_xact_id()::xid::text AS txid`,
    );
    return { task, txid: Number(xid.rows[0]!.txid) };
  });
}
