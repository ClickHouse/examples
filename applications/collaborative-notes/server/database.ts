import { readFileSync } from "node:fs";
import pg, { type PoolConfig } from "pg";
export function databaseConfig(
  env: NodeJS.ProcessEnv = process.env,
): PoolConfig {
  for (const key of [
    "PGHOST",
    "PGDATABASE",
    "PGUSER",
    "PGPASSWORD",
    "PGSSLROOTCERT",
  ]) {
    if (!env[key]) throw new Error(`Missing ${key}.`);
  }
  if (env.PGSSLMODE !== "verify-full")
    throw new Error("PGSSLMODE must be verify-full.");
  const port = Number(env.PGPORT ?? "5432");
  if (!Number.isInteger(port) || port < 1 || port > 65535)
    throw new Error("PGPORT must be an integer from 1 to 65535.");
  if (
    !/^(?=.{1,253}$)[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$/.test(
      env.PGHOST!,
    )
  )
    throw new Error("PGHOST must be one DNS hostname or IPv4 address.");
  return {
    host: env.PGHOST,
    port,
    database: env.PGDATABASE,
    user: env.PGUSER,
    password: env.PGPASSWORD,
    ssl: {
      ca: readFileSync(env.PGSSLROOTCERT!, "utf8"),
      rejectUnauthorized: true,
    },
    max: 4,
    connectionTimeoutMillis: 5000,
    idleTimeoutMillis: 30000,
    maxLifetimeSeconds: 900,
    statement_timeout: 10000,
    lock_timeout: 5000,
    idle_in_transaction_session_timeout: 15000,
    application_name: "collaborative-notes",
  };
}
export function createPool(env: NodeJS.ProcessEnv = process.env): pg.Pool {
  const pool = new pg.Pool(databaseConfig(env));
  pool.on("error", () => console.error("An idle database connection failed."));
  return pool;
}
