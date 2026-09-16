import { getClickHouse, transaction } from "./db";
import type { ClickEvent } from "../lib/types";
import { z } from "zod";

/** Run from a persistent worker/scheduler. It is safe for several workers to overlap. */
export async function flushOutbox(
  batchSize = 500,
  accountId?: string,
): Promise<{ delivered: number; failed: number }> {
  if (!Number.isInteger(batchSize) || batchSize < 1 || batchSize > 1000)
    throw new Error("Batch size must be between 1 and 1,000.");
  // Trusted maintenance callers may drain one account without touching others.
  if (accountId !== undefined) z.string().uuid().parse(accountId);
  const client = getClickHouse();
  return transaction(async (db) => {
    const batch = await db.query(
      `SELECT event_id, event FROM click_outbox WHERE next_attempt_at <= now()
      AND ($2::uuid IS NULL OR account_id = $2)
      ORDER BY created_at LIMIT $1 FOR UPDATE SKIP LOCKED`,
      [batchSize, accountId ?? null],
    );
    if (!batch.rows.length) return { delivered: 0, failed: 0 };
    const ids = batch.rows.map((row) => row.event_id as string);
    try {
      await client.insert({
        table: "click_events",
        values: batch.rows.map((row) => row.event as ClickEvent),
        format: "JSONEachRow",
        clickhouse_settings: { async_insert: 1, wait_for_async_insert: 1 },
      });
    } catch {
      await db.query(
        `UPDATE click_outbox SET attempts = attempts + 1,
        next_attempt_at = now() + make_interval(secs => LEAST(300, power(2, LEAST(attempts + 1, 8))::integer))
        WHERE event_id = ANY($1::uuid[])`,
        [ids],
      );
      // Never log payloads or raw driver errors: destination campaign values may be sensitive.
      console.error("Click event delivery failed; durable events will retry.");
      return { delivered: 0, failed: ids.length };
    }
    await db.query(
      "DELETE FROM click_outbox WHERE event_id = ANY($1::uuid[])",
      [ids],
    );
    // If acknowledgement or commit is lost, the immutable event is retried. Reports use uniqExact.
    return { delivered: ids.length, failed: 0 };
  });
}
