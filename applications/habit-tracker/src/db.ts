import { readFileSync } from "node:fs";
import { drizzle } from "drizzle-orm/node-postgres";
import { Pool, type PoolConfig } from "pg";
import * as schema from "./schema";

export function poolConfig(
  env: Record<string, string | undefined> = process.env,
): PoolConfig {
  const connectionString = env.DATABASE_URL;
  if (!connectionString)
    throw new Error("Set DATABASE_URL (see .env.example).");
  // pg lets URL parameters such as sslmode replace the ssl object below, so keep
  // TLS settings out of the URL.
  if (new URL(connectionString).search) {
    throw new Error(
      "DATABASE_URL must not have query parameters; set PGSSLROOTCERT for TLS.",
    );
  }
  return {
    connectionString,
    ssl: tlsOptions(connectionString, env.PGSSLROOTCERT),
    max: 5,
    connectionTimeoutMillis: 5_000,
    idleTimeoutMillis: 30_000,
    statement_timeout: 5_000,
    application_name: "habit-tracker",
  };
}

// ClickHouse Managed Postgres: verify the server certificate and hostname
// against the service CA from `clickhousectl cloud postgres certs get`.
// Everything else in this file is plain Postgres.
export function tlsOptions(
  connectionString: string,
  caPath: string | undefined,
) {
  if (caPath)
    return { ca: readFileSync(caPath, "utf8"), rejectUnauthorized: true };
  // Local Postgres from `clickhousectl local postgres` has no TLS. Anything
  // else must have a CA, so a missing variable can't silently disable TLS.
  if (LOCAL_HOSTS.has(new URL(connectionString).hostname)) return false;
  throw new Error("Set PGSSLROOTCERT to the CA file for a remote database.");
}

const LOCAL_HOSTS = new Set(["localhost", "127.0.0.1", "[::1]"]);

export function createDb(
  env: Record<string, string | undefined> = process.env,
) {
  return drizzle({ client: new Pool(poolConfig(env)), schema });
}

export type Db = ReturnType<typeof createDb>;

// One pool per server process. The global survives Next.js hot reloads in dev.
const globalForDb = globalThis as unknown as { habitTrackerDb?: Db };

export function getDb(): Db {
  globalForDb.habitTrackerDb ??= createDb();
  return globalForDb.habitTrackerDb;
}
