import { setTimeout as delay } from "node:timers/promises";
import type { Db, Job } from "pg-boss";
import { uuid } from "./input.js";
export type ImportJob = { importId: string };
export type Fault = {
  importId: string;
  failAttempts: number;
  pauseAfterEffects: boolean;
};
export function testFault(): Fault | undefined {
  if (!process.env.TEST_IMPORT_ID) return undefined;
  const failAttempts = Number(process.env.TEST_FAIL_ATTEMPTS ?? "0");
  if (
    process.env.NODE_ENV !== "test" ||
    !uuid(process.env.TEST_IMPORT_ID) ||
    !Number.isInteger(failAttempts) ||
    failAttempts < 0 ||
    failAttempts > 3
  )
    throw new Error("Invalid test-only worker fault");
  return {
    importId: process.env.TEST_IMPORT_ID,
    failAttempts,
    pauseAfterEffects: process.env.TEST_PAUSE_AFTER_EFFECTS === "true",
  };
}
export async function processImport(
  jobs: Job<ImportJob>[],
  tx: Db,
  fault?: Fault,
) {
  const job = jobs[0];
  if (!job || !uuid(job.data?.importId))
    throw new Error("Invalid import job reference");
  const {
    rows: [record],
  } = await tx.executeSql(
    "SELECT * FROM contact_imports.imports WHERE id = $1 FOR UPDATE",
    [job.data.importId],
  );
  if (!record) throw new Error("Import no longer exists");
  if (record.state !== "queued")
    return { state: record.state, rowsImported: record.result_count };
  await tx.executeSql(
    `INSERT INTO contact_imports.contacts (import_id, account_id, row_index, email, name)
    SELECT $1::uuid, $2::uuid, r.position::integer, r.record->>'email', r.record->>'name'
    FROM jsonb_array_elements($3::jsonb) WITH ORDINALITY AS r(record, position)
    ON CONFLICT (import_id, email) DO NOTHING`,
    [record.id, record.account_id, JSON.stringify(record.payload)],
  );
  const {
    rows: [counts],
  } = await tx.executeSql(
    "SELECT count(*)::integer AS total FROM contact_imports.contacts WHERE import_id = $1",
    [record.id],
  );
  if (counts.total !== record.row_count)
    throw new Error("Import effects disagree with the durable payload");
  await tx.executeSql(
    "UPDATE contact_imports.imports SET state = 'succeeded', result_count = $2, finished_at = clock_timestamp() WHERE id = $1",
    [record.id, counts.total],
  );
  if (fault && fault.importId === record.id) {
    process.send?.({ type: "effects_written", importId: record.id });
    if (job.retryCount < fault.failAttempts)
      throw new Error("Bounded test-only import failure");
    if (fault.pauseAfterEffects)
      await delay(15_000, undefined, { signal: job.signal });
  }
  return { state: "succeeded", rowsImported: counts.total };
}
