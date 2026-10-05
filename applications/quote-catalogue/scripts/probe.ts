import { lookup } from "node:dns/promises";
import { createDb, connection } from "../src/server/db";
const config = connection();
if (process.argv.includes("--wrong-host")) {
  config.host = (await lookup(config.host!)).address;
  config.ssl = { ...(config.ssl as object), servername: "wrong.example" };
}
const db = createDb(config);
try {
  const { sql } = await import("kysely");
  console.log(
    await sql`SELECT current_user AS role, version() AS version`.execute(db),
  );
} catch (error) {
  console.error((error as Error).name, (error as Error).message);
  process.exitCode = 1;
} finally {
  await db.destroy();
}
