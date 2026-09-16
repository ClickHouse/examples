import { readFileSync } from "node:fs";
import { Pool, type PoolClient } from "pg";
import { ClickHouseLogLevel, createClient } from "@clickhouse/client-web";
import { getWorkersRuntime, runtimeEnvironment } from "./runtime";

let postgres: Pool | undefined;
let clickhouse: ReturnType<typeof createClient> | undefined;

export function getPostgres(): Pool {
  const runtime = getWorkersRuntime();
  if (runtime) {
    if (!runtime.postgres) {
      runtime.postgres = new Pool({
        connectionString: runtime.env.HYPERDRIVE.connectionString,
        // Hyperdrive maintains the origin pool and TLS connection. These
        // lightweight clients are scoped to this invocation only.
        max: 5,
        connectionTimeoutMillis: 5000,
        idleTimeoutMillis: 10_000,
        statement_timeout: 10_000,
      });
      runtime.postgres.on("error", () =>
        console.error("An idle Postgres connection failed."),
      );
    }
    return runtime.postgres;
  }
  if (postgres) return postgres;
  const value = process.env.DATABASE_URL;
  if (!value) throw new Error("DATABASE_URL is not configured.");
  const connection = new URL(value);
  const caPath = process.env.PG_CA_CERT_PATH;
  const local = ["localhost", "127.0.0.1", "::1", "[::1]"].includes(
    connection.hostname,
  );
  // pg's URL SSL arguments replace explicit SSL options, including a supplied CA.
  // Remote connections always verify the server; local development can be plain TCP.
  for (const key of ["sslmode", "sslcert", "sslkey", "sslrootcert"])
    connection.searchParams.delete(key);
  postgres = new Pool({
    connectionString: connection.toString(),
    ssl: caPath
      ? { ca: readFileSync(caPath, "utf8"), rejectUnauthorized: true }
      : local
        ? false
        : { rejectUnauthorized: true },
    max: 10,
    connectionTimeoutMillis: 5000,
    idleTimeoutMillis: 30_000,
    statement_timeout: 10_000,
  });
  postgres.on("error", () =>
    console.error("An idle Postgres connection failed."),
  );
  return postgres;
}

export function getClickHouse() {
  const runtime = getWorkersRuntime();
  const existing = runtime ? runtime.clickhouse : clickhouse;
  if (existing) return existing;
  const url = runtimeEnvironment("CLICKHOUSE_URL");
  if (!url)
    throw new Error("ClickHouse analytics is not configured.");
  const client = createClient({
    url,
    username: runtimeEnvironment("CLICKHOUSE_USERNAME") || "default",
    password: runtimeEnvironment("CLICKHOUSE_PASSWORD") || "",
    database: runtimeEnvironment("CLICKHOUSE_DATABASE") || "default",
    request_timeout: 10_000,
    // Driver errors can include query or event values. Callers emit safe status
    // messages instead of sending raw server responses to application logs.
    log: { level: ClickHouseLogLevel.OFF },
  });
  if (runtime) runtime.clickhouse = client;
  else clickhouse = client;
  return client;
}

export async function transaction<T>(
  fn: (client: PoolClient) => Promise<T>,
): Promise<T> {
  const client = await getPostgres().connect();
  try {
    await client.query("BEGIN");
    const result = await fn(client);
    await client.query("COMMIT");
    return result;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function closeDatabases() {
  await Promise.all([postgres?.end(), clickhouse?.close()]);
  postgres = undefined;
  clickhouse = undefined;
}
