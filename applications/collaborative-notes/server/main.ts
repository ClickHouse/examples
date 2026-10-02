import { createPool } from "./database.js";
import { PostgresStorage } from "./store.js";
import { createServer } from "./protocol.js";
if (process.env.PGUSER !== "notes_runtime")
  throw new Error("Start the server using only notes_runtime credentials.");
const pool = createPool();
const storage = new PostgresStorage(pool);
await storage.verify();
const server = createServer(storage, process.env.WORKSPACE_TOKEN ?? "");
await server.listen();
console.log("Collaborative notes listening on loopback port 1234.");
let stopping = false;
async function shutdown(): Promise<void> {
  if (stopping) return;
  stopping = true;
  // A failed Hocuspocus store may retain an in-memory document. Bound shutdown;
  // never describe an unconfirmed snapshot as durable merely because we exit.
  const timeout = setTimeout(() => {
    console.error("Shutdown deadline reached; uncommitted edits may be lost.");
    process.exit(1);
  }, 20000);
  try {
    await server.destroy();
    await pool.end();
    clearTimeout(timeout);
    process.exit(0);
  } catch {
    console.error("Shutdown failed; uncommitted edits may be lost.");
    process.exit(1);
  }
}
process.on("SIGTERM", () => void shutdown());
process.on("SIGINT", () => void shutdown());
