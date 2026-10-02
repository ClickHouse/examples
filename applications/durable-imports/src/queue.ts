import { PgBoss } from "pg-boss";
import { databaseConfig } from "./database.js";
export const QUEUE = "contact-imports";
export const SCHEMA = "import_jobs";
export const RETRY_LIMIT = 2;
export const QUEUE_OPTIONS = {
  retryLimit: RETRY_LIMIT,
  retryDelay: 1,
  retryBackoff: true,
  retryDelayMax: 4,
  expireInSeconds: 20,
  heartbeatSeconds: 10,
  retentionSeconds: 3600,
  deleteAfterSeconds: 86400,
  partition: false,
  notify: false,
};
export function queue(worker = false, migrate = false): PgBoss {
  const boss = new PgBoss({
    ...databaseConfig(),
    schema: SCHEMA,
    migrate,
    createSchema: false,
    supervise: worker,
    schedule: false,
    reindex: false,
    persistQueueStats: false,
    persistWarnings: false,
    superviseIntervalSeconds: 2,
    monitorIntervalSeconds: 2,
    queueCacheIntervalSeconds: 10,
    maintenanceIntervalSeconds: 60,
    max: 5,
  });
  // Never print SQL parameters, credentials or contact payloads to application logs.
  boss.on("error", () => console.error("Queue operation error"));
  boss.on("warning", (warning) =>
    console.error(
      "Queue warning",
      warning.data && "type" in warning.data
        ? String(warning.data.type)
        : "unspecified",
    ),
  );
  return boss;
}
