import { randomUUID } from "node:crypto";
import type { Pool, PoolClient } from "pg";
import type { PgBoss } from "pg-boss";
import { transaction, transactionAdapter } from "./database.js";
import { ApiError, MAX_DAILY, MAX_PENDING, normalize } from "./input.js";
import { QUEUE } from "./queue.js";

// Terminal queue outcomes are copied to the durable application record. Missing
// metadata is reported honestly, including after queue retention or operator deletion.
export async function reconcile(
  db: Pick<PoolClient, "query">,
  accountId?: string,
): Promise<void> {
  await db.query(
    `
    UPDATE contact_imports.imports AS i SET state = 'failed', finished_at = clock_timestamp(),
      error = CASE j.state::text
        WHEN 'failed' THEN 'Queue retry limit exhausted'
        WHEN 'cancelled' THEN 'Queue job cancelled'
        WHEN 'completed' THEN 'Queue completion has no application result'
        ELSE 'Queue metadata no longer available' END
    FROM (SELECT x.id, q.state FROM contact_imports.imports x
      LEFT JOIN import_jobs.job q ON q.id = x.id AND q.name = $1
      WHERE x.state = 'queued' AND ($2::uuid IS NULL OR x.account_id = $2)
        AND (q.id IS NULL OR q.state::text IN ('failed', 'cancelled', 'completed'))) j
    WHERE i.id = j.id AND i.state = 'queued'`,
    [QUEUE, accountId ?? null],
  );
}
export class Imports {
  constructor(
    private db: Pool,
    private boss: PgBoss,
  ) {}
  async submit(
    accountId: string,
    input: unknown,
    afterEnqueue?: () => Promise<void>,
  ) {
    if (afterEnqueue && process.env.NODE_ENV !== "test")
      throw new Error("Submission fault requires test mode");
    const normalized = normalize(input);
    return transaction(this.db, async (client) => {
      const {
        rows: [account],
      } = await client.query(
        "SELECT id, window_start, submission_count FROM contact_imports.accounts WHERE id = $1 FOR UPDATE",
        [accountId],
      );
      if (!account) throw new ApiError(401, "unknown_account");
      const {
        rows: [existing],
      } = await client.query(
        "SELECT id, fingerprint FROM contact_imports.imports WHERE account_id = $1 AND request_id = $2",
        [accountId, normalized.requestId],
      );
      if (existing) {
        if (existing.fingerprint !== normalized.fingerprint)
          throw new ApiError(409, "request_id_conflict");
        return { id: existing.id as string, replay: true };
      }
      await reconcile(client, accountId);
      const {
        rows: [limits],
      } = await client.query(
        `SELECT
        count(*)::integer AS pending,
        clock_timestamp() >= $2::timestamptz + interval '24 hours' AS reset
        FROM contact_imports.imports WHERE account_id = $1 AND state = 'queued'`,
        [accountId, account.window_start],
      );
      const count = limits.reset ? 0 : account.submission_count;
      if (limits.pending >= MAX_PENDING || count >= MAX_DAILY)
        throw new ApiError(429, "account_import_limit");
      await client.query(
        "UPDATE contact_imports.accounts SET submission_count = $2, window_start = CASE WHEN $3 THEN clock_timestamp() ELSE window_start END WHERE id = $1",
        [accountId, count + 1, limits.reset],
      );
      const id = randomUUID();
      await client.query(
        "INSERT INTO contact_imports.imports (id, account_id, request_id, fingerprint, payload, row_count) VALUES ($1, $2, $3, $4, $5, $6)",
        [
          id,
          accountId,
          normalized.requestId,
          normalized.fingerprint,
          JSON.stringify(normalized.rows),
          normalized.rows.length,
        ],
      );
      const jobId = await this.boss.send(
        QUEUE,
        { importId: id },
        { id, db: transactionAdapter(client) },
      );
      if (jobId !== id) throw new Error("Queue did not accept the import job");
      // Internal acceptance seam, never accepted from an HTTP request.
      if (afterEnqueue) await afterEnqueue();
      return { id, replay: false };
    });
  }
  async status(accountId: string, id: string) {
    return transaction(this.db, async (client) => {
      await reconcile(client, accountId);
      const {
        rows: [row],
      } = await client.query(
        `SELECT i.id, i.request_id AS "requestId", i.state,
        i.row_count AS "rowCount", i.result_count AS "rowsImported", i.error,
        i.created_at AS "createdAt", i.finished_at AS "finishedAt", j.state::text AS "queueState",
        j.retry_count AS "retryCount"
        FROM contact_imports.imports i LEFT JOIN import_jobs.job j ON j.id = i.id AND j.name = $3
        WHERE i.id = $1 AND i.account_id = $2`,
        [id, accountId, QUEUE],
      );
      if (!row) throw new ApiError(404, "import_not_found");
      return row;
    });
  }
  async results(accountId: string, id: string) {
    const status = await this.status(accountId, id);
    if (status.state !== "succeeded")
      throw new ApiError(409, "import_not_succeeded");
    const { rows } = await this.db.query(
      "SELECT email, name FROM contact_imports.contacts WHERE import_id = $1 AND account_id = $2 ORDER BY row_index",
      [id, accountId],
    );
    return rows;
  }
}
