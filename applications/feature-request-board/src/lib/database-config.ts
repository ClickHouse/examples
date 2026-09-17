import { readFileSync } from "node:fs";
import type { PoolConfig } from "pg";

export function databaseConfig(
  env: Record<string, string | undefined> = process.env,
): PoolConfig {
  if (!env.DATABASE_URL || !env.DATABASE_CA_PATH) {
    throw new Error(
      "Set DATABASE_URL and DATABASE_CA_PATH before starting the app.",
    );
  }
  const url = new URL(env.DATABASE_URL);
  if (
    !["postgresql:", "postgres:"].includes(url.protocol) ||
    !url.hostname ||
    !url.username ||
    !url.password
  ) {
    throw new Error(
      "DATABASE_URL must be a complete PostgreSQL connection URL.",
    );
  }
  // pg URL options can replace the explicit ssl object and silently lose its CA.
  // The Prisma schema is selected by the adapter, not by a URL query parameter.
  if (url.search)
    throw new Error(
      "Use a plain DATABASE_URL without query parameters; TLS is configured with DATABASE_CA_PATH.",
    );
  return {
    connectionString: env.DATABASE_URL,
    ssl: {
      ca: readFileSync(env.DATABASE_CA_PATH, "utf8"),
      rejectUnauthorized: true,
    },
    max: 5,
    connectionTimeoutMillis: 5000,
    idleTimeoutMillis: 30000,
    statement_timeout: 10000,
    application_name: "feature-request-board",
  };
}
