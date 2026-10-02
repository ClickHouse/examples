import { readFileSync } from "node:fs";
import knex from "knex";
export function databaseConfig(env = process.env) {
  for (const key of [
    "PGHOST",
    "PGUSER",
    "PGPASSWORD",
    "PGDATABASE",
    "PGSSLROOTCERT",
  ]) {
    if (!env[key]) throw new Error(`${key} is required`);
  }
  return {
    client: "pg",
    searchPath: ["directory"],
    connection: {
      host: env.PGHOST,
      port: Number(env.PGPORT || 5432),
      database: env.PGDATABASE,
      user: env.PGUSER,
      password: env.PGPASSWORD,
      ssl: {
        ca: readFileSync(env.PGSSLROOTCERT, "utf8"),
        rejectUnauthorized: true,
      },
      connectionTimeoutMillis: 10000,
      statement_timeout: 15000,
      application_name: "team-directory",
    },
    pool: { min: 0, max: 4, acquireTimeoutMillis: 12000 },
  };
}
let pool;
export function database() {
  return (pool ||= knex(databaseConfig()));
}
