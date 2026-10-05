import { getPool } from "./db";
import type { PoolClient } from "pg";
import { TRPCError } from "@trpc/server";
import type { Detail, Summary, Edit, Decision } from "../shared/schema";
type Header = {
  id: number;
  employee: string;
  category: string;
  submitted_at: Date;
  status: "pending" | "approved" | "rejected";
  revision: number;
  memo: string;
  total_cents: number;
};
const map = (row: Header): Summary => ({
  id: row.id,
  employee: row.employee,
  category: row.category,
  submittedAt: row.submitted_at.toISOString(),
  status: row.status,
  revision: row.revision,
  memo: row.memo,
  totalCents: row.total_cents,
});
const selectHeader = `SELECT c.*,COALESCE((SELECT SUM(amount_cents) FROM line_items WHERE claim_id=c.id),0)::integer AS total_cents FROM claims c`;
export async function readList() {
  const client = await getPool().connect();
  try {
    await client.query("BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY");
    const rows = (await client.query<Header>(selectHeader + " ORDER BY c.id"))
      .rows;
    const count = (
      await client.query<{ count: number }>(
        "SELECT COUNT(*)::integer AS count FROM claims",
      )
    ).rows[0]!.count;
    await client.query("COMMIT");
    return { claims: rows.map(map), totalCount: count };
  } catch (e) {
    await client.query("ROLLBACK");
    throw e;
  } finally {
    client.release();
  }
}
async function detailFrom(client: PoolClient, id: number): Promise<Detail> {
  const row = (
    await client.query<Header>(selectHeader + " WHERE c.id=$1", [id])
  ).rows[0];
  if (!row)
    throw new TRPCError({
      code: "NOT_FOUND",
      message: "That claim does not exist.",
    });
  const lines = (
    await client.query<{ description: string; amountCents: number }>(
      'SELECT description,amount_cents AS "amountCents" FROM line_items WHERE claim_id=$1 ORDER BY position',
      [id],
    )
  ).rows;
  const history = (
    await client.query<{
      id: number;
      reviewedRevision: number;
      decision: "approved" | "rejected";
      reason: string;
      memoSnapshot: string;
      totalCents: number;
      snapshot: Detail["lines"];
      decidedAt: Date;
    }>(
      'SELECT id,reviewed_revision AS "reviewedRevision",decision,reason,memo_snapshot AS "memoSnapshot",total_cents AS "totalCents",line_snapshot AS snapshot,decided_at AS "decidedAt" FROM decisions WHERE claim_id=$1 ORDER BY id DESC',
      [id],
    )
  ).rows.map((row) => ({ ...row, decidedAt: row.decidedAt.toISOString() }));
  return { ...map(row), lines, history };
}
export async function readDetail(id: number) {
  const client = await getPool().connect();
  try {
    await client.query("BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY");
    const result = await detailFrom(client, id);
    await client.query("COMMIT");
    return result;
  } catch (e) {
    await client.query("ROLLBACK");
    throw e;
  } finally {
    client.release();
  }
}
async function lockRevision(client: PoolClient, id: number, revision: number) {
  const row = (
    await client.query<{ revision: number; status: string }>(
      "SELECT revision,status FROM claims WHERE id=$1 FOR UPDATE",
      [id],
    )
  ).rows[0];
  if (!row)
    throw new TRPCError({
      code: "NOT_FOUND",
      message: "That claim does not exist.",
    });
  if (row.revision !== revision)
    throw new TRPCError({
      code: "CONFLICT",
      message:
        "This claim changed after you loaded it. Reload the saved revision before reviewing.",
    });
  return row;
}
export async function editClaim(input: Edit) {
  const client = await getPool().connect();
  try {
    await client.query("BEGIN");
    await lockRevision(client, input.id, input.revision);
    await client.query(
      "UPDATE claims SET memo=$1,status='pending',revision=revision+1 WHERE id=$2",
      [input.memo, input.id],
    );
    await client.query("DELETE FROM line_items WHERE claim_id=$1", [input.id]);
    for (const [position, line] of input.lines.entries())
      await client.query(
        "INSERT INTO line_items(claim_id,position,description,amount_cents) VALUES($1,$2,$3,$4)",
        [input.id, position, line.description, line.amountCents],
      );
    const result = await detailFrom(client, input.id);
    await client.query("COMMIT");
    return result;
  } catch (e) {
    await client.query("ROLLBACK");
    throw e;
  } finally {
    client.release();
  }
}
export async function decideClaim(input: Decision) {
  const client = await getPool().connect();
  try {
    await client.query("BEGIN");
    const row = await lockRevision(client, input.id, input.revision);
    if (row.status !== "pending")
      throw new TRPCError({
        code: "CONFLICT",
        message:
          "This revision already has a decision. Amend it before reviewing again.",
      });
    const reviewed = await detailFrom(client, input.id);
    await client.query(
      "INSERT INTO decisions(claim_id,reviewed_revision,decision,reason,total_cents,line_snapshot,memo_snapshot) VALUES($1,$2,$3,$4,$5,$6::jsonb,$7)",
      [
        input.id,
        input.revision,
        input.decision,
        input.reason,
        reviewed.totalCents,
        JSON.stringify(reviewed.lines),
        reviewed.memo,
      ],
    );
    await client.query(
      "UPDATE claims SET status=$1,revision=revision+1 WHERE id=$2",
      [input.decision, input.id],
    );
    const result = await detailFrom(client, input.id);
    await client.query("COMMIT");
    return result;
  } catch (e) {
    await client.query("ROLLBACK");
    throw e;
  } finally {
    client.release();
  }
}
