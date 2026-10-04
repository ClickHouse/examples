import { and, eq, sql } from "drizzle-orm";
import type { Database } from "./database";
import { graphs, revisions } from "./schema";
import type { GraphDocument, SavedGraph } from "../shared/types";
export class StaleRevision extends Error {}
function view(row: typeof graphs.$inferSelect): SavedGraph {
  return { ...row, updatedAt: row.updatedAt.toISOString() };
}
export async function readGraph(db: Database, id: string) {
  const [row] = await db.select().from(graphs).where(eq(graphs.id, id));
  return row ? view(row) : undefined;
}
export async function saveGraph(
  db: Database,
  id: string,
  baseRevision: number,
  document: GraphDocument,
) {
  return db.transaction(async (tx) => {
    const [saved] = await tx
      .update(graphs)
      .set({
        revision: baseRevision + 1,
        document,
        updatedAt: sql`clock_timestamp()`,
      })
      .where(and(eq(graphs.id, id), eq(graphs.revision, baseRevision)))
      .returning();
    if (!saved)
      throw new StaleRevision("The graph changed. Reload before saving.");
    await tx
      .insert(revisions)
      .values({ graphId: id, revision: saved.revision, document });
    return view(saved);
  });
}
