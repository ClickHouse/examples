import type { Db, Job } from "pg-boss";
import { pool } from "./database.js";
import { processImport, testFault, type ImportJob } from "./handler.js";
import { reconcile } from "./imports.js";
import { QUEUE, queue } from "./queue.js";
if (process.env.PGUSER !== "imports_worker")
  throw new Error("Worker requires the imports_worker role");
const db = pool();
const boss = queue(true);
const fault = testFault();
// Preserve terminal outcomes before the queue supervisor can prune old metadata.
await reconcile(db);
await boss.start();
await boss.work(
  QUEUE,
  {
    transactional: true,
    transactionTimeoutSeconds: 25,
    batchSize: 1,
    localConcurrency: 1,
    pollingIntervalSeconds: 0.5,
  },
  (jobs: Job<ImportJob>[], tx: Db) => processImport(jobs, tx, fault),
);
console.log("Import worker ready");
process.send?.({ type: "ready" });
let reconciling = false;
const timer = setInterval(() => {
  if (reconciling) return;
  reconciling = true;
  void reconcile(db)
    .catch(() => console.error("Import outcome reconciliation failed"))
    .finally(() => {
      reconciling = false;
    });
}, 1000);
let stopping = false;
async function stop() {
  if (stopping) return;
  stopping = true;
  clearInterval(timer);
  await boss.stop({ graceful: true, timeout: 25_000 });
  await db.end();
}
process.on("SIGTERM", () => void stop());
process.on("SIGINT", () => void stop());
