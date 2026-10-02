import { queue, QUEUE, QUEUE_OPTIONS } from "../src/queue.js";
if (process.env.PGUSER !== "imports_migration")
  throw new Error("Queue setup requires imports_migration");
// The explicit owner-only command invokes pg-boss's pinned standard migrations.
// Runtime instances use migrate:false and never create queues or partitions.
const boss = queue(false, true);
try {
  await boss.start();
  await boss.createQueue(QUEUE, QUEUE_OPTIONS);
  const { partition: _partition, ...mutableOptions } = QUEUE_OPTIONS;
  await boss.updateQueue(QUEUE, mutableOptions);
  console.log("Queue schema version", await boss.schemaVersion());
} finally {
  await boss.stop();
}
