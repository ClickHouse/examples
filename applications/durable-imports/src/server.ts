import { createApp } from "./app.js";
import { pool } from "./database.js";
import { Imports } from "./imports.js";
import { queue } from "./queue.js";
if (process.env.PGUSER !== "imports_api")
  throw new Error("Server requires the imports_api role");
const db = pool();
const boss = queue();
await boss.start();
const port = Number(process.env.PORT ?? "4000");
if (!Number.isInteger(port) || port < 1 || port > 65535)
  throw new Error("Invalid PORT");
const server = createApp(new Imports(db, boss)).listen(port, "127.0.0.1", () =>
  console.log("Import API listening on loopback"),
);
let stopping = false;
async function stop() {
  if (stopping) return;
  stopping = true;
  server.close();
  await boss.stop();
  await db.end();
}
process.on("SIGTERM", () => void stop());
process.on("SIGINT", () => void stop());
