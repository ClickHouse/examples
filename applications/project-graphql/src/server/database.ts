import { Pool } from "pg";
import { readFileSync } from "node:fs";
export async function connectDatabase(
  urlText = process.env.DATABASE_URL,
  caPath = process.env.PG_CA_CERT_PATH,
) {
  if (!urlText) throw new Error("DATABASE_URL required");
  const url = new URL(urlText);
  if (
    !["postgres:", "postgresql:"].includes(url.protocol) ||
    url.search ||
    url.hash
  )
    throw new Error("Use a plain Postgres URL without query overrides");
  const local = process.env.DATABASE_LOCAL === "true";
  if (local && !["127.0.0.1", "localhost", "[::1]"].includes(url.hostname))
    throw new Error("Local mode requires loopback");
  if (!local && !caPath) throw new Error("Supplied CA required");
  const pool = new Pool({
    connectionString: url.toString(),
    max: 5,
    connectionTimeoutMillis: 10000,
    ssl: local
      ? false
      : {
          ca: readFileSync(caPath!, "utf8"),
          servername: url.hostname,
          rejectUnauthorized: true,
        },
  });
  try {
    await pool.query("SELECT 1");
    return pool;
  } catch (error) {
    await pool.end();
    throw error;
  }
}
