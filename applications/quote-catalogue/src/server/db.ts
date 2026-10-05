import { readFileSync } from "node:fs";
import pg from "pg";
import { Kysely, PostgresDialect, type ColumnType } from "kysely";
interface Products {
  id: number;
  name: string;
  category: string;
  description: string;
  rate_minor: number;
}
interface Quotes {
  id: number;
  title: string;
  days: number;
  revision: number;
  updated_at: ColumnType<Date, string, string>;
}
interface Lines {
  quote_id: number;
  product_id: number;
  quantity: number;
  unit_minor: number;
}
export interface Database {
  products: Products;
  quotes: Quotes;
  quote_lines: Lines;
}
export function connection(overrides: pg.PoolConfig = {}): pg.PoolConfig {
  const required = (key: string) => {
    const v = process.env[key];
    if (!v) throw new Error(`Missing ${key}`);
    return v;
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
export function createDb(overrides: pg.PoolConfig = {}) {
  return new Kysely<Database>({
    dialect: new PostgresDialect({ pool: new pg.Pool(connection(overrides)) }),
  });
}
let db: Kysely<Database> | undefined;
export function getDb() {
  return (db ??= createDb());
}
