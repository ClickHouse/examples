import { lookup } from "node:dns/promises";
import pg from "pg";
import { connection } from "../src/server/db";
const config = connection();
if (process.argv.includes("--wrong-host")) {
  config.host = (await lookup(config.host!)).address;
  config.ssl = { ...(config.ssl as object), servername: "wrong.example" };
}
const pool = new pg.Pool(config);
try {
  console.log(
    (await pool.query("SELECT current_user AS role,version() AS version")).rows,
  );
} catch (error) {
  console.error((error as Error).name, (error as Error).message);
  process.exitCode = 1;
} finally {
  await pool.end();
}
