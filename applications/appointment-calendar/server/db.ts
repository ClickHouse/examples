import { readFileSync } from "node:fs";
import pg from "pg";
export function connection(overrides: pg.PoolConfig = {}): pg.PoolConfig {
  const required = (key: string) => {
    const value = process.env[key];
    if (!value) throw new Error(`Missing ${key}`);
    return value;
  };
  return {
    host: required("DB_HOST"),
    port: Number(process.env.DB_PORT ?? "5432"),
    database: required("DB_DATABASE"),
    user: required("DB_USER"),
    password: required("DB_PASSWORD"),
    max: 5,
    ssl: {
      ca: readFileSync(required("PG_CA_CERT_PATH"), "utf8"),
      rejectUnauthorized: true,
      servername: required("DB_HOST"),
    },
    ...overrides,
  };
}
export function createPool(overrides: pg.PoolConfig = {}) {
  return new pg.Pool(connection(overrides));
}
let pool: pg.Pool | undefined;
export function getPool() {
  return (pool ??= createPool());
}
