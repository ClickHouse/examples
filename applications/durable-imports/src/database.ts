import { readFileSync } from "node:fs";
import pg, { type PoolClient, type PoolConfig } from "pg";
import type { Db } from "pg-boss";

export function databaseConfig(): PoolConfig {
  const required = (name: string): string => {
    const value = process.env[name];
    if (!value) throw new Error(`${name} is required`);
    return value;
  };
  const port = Number(process.env.PGPORT ?? "5432");
  if (!Number.isInteger(port) || port < 1 || port > 65535)
    throw new Error("Invalid PGPORT");
  const host = required("PGHOST");
  return {
    host,
    port,
    database: required("PGDATABASE"),
    user: required("PGUSER"),
    password: required("PGPASSWORD"),
    ssl: {
      ca: readFileSync(required("PGSSLROOTCERT"), "utf8"),
      rejectUnauthorized: true,
      servername: host,
    },
    max: 5,
    connectionTimeoutMillis: 15_000,
    statement_timeout: 15_000,
    idleTimeoutMillis: 10_000,
  };
}
export function pool(): pg.Pool {
  const result = new pg.Pool(databaseConfig());
  result.on("error", () => console.error("Database idle connection error"));
  return result;
}
// The adapter executes every pg-boss statement on this already-open transaction.
export function transactionAdapter(client: PoolClient): Db {
  return { executeSql: (text, values) => client.query(text, values) };
}
export async function transaction<T>(
  db: pg.Pool,
  callback: (client: PoolClient) => Promise<T>,
): Promise<T> {
  const client = await db.connect();
  let discarded: Error | undefined;
  try {
    await client.query("BEGIN");
    const value = await callback(client);
    await client.query("COMMIT");
    return value;
  } catch (error) {
    try {
      await client.query("ROLLBACK");
    } catch (rollbackError) {
      discarded = rollbackError as Error;
    }
    throw error;
  } finally {
    client.release(discarded);
  }
}
