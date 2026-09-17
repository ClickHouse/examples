import { createApp } from "./app.ts";
import type { SQL } from "bun";
import { loadConfig } from "./config.ts";
import { createDatabase } from "./database.ts";

const config = loadConfig();
let sql: SQL;
try {
  sql = await createDatabase(config.database);
} catch {
  console.error("Could not connect to PostgreSQL. Check the URL, CA certificate, and service access settings.");
  process.exit(1);
}
const app = createApp({
  sql,
  apiKeys: config.apiKeys,
  onError: () => console.error("A database request failed; the client can retry with the same idempotency key."),
});
const server = Bun.serve({
  hostname: config.hostname,
  port: config.port,
  fetch: app.fetch,
  idleTimeout: 15,
  // A second transport cap protects routes that do not consume a body.
  // POST /reservations enforces its own 4 KiB cap and returns a JSON error.
  maxRequestBodySize: 64 * 1024,
});
console.log(`Stock Reservation is listening on ${server.url}`);

let stopping = false;
async function shutdown() {
  if (stopping) return;
  stopping = true;
  const deadline = setTimeout(() => {
    void server.stop(true);
    void sql.close({ timeout: 0 });
    process.exit(1);
  }, 10_000);
  deadline.unref();
  await server.stop();
  await sql.close({ timeout: 5 });
  clearTimeout(deadline);
}
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
