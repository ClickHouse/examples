import { defineConfig } from "drizzle-kit";
import { tlsOptions } from "./src/db";

// drizzle-kit opens its own connection, so it needs the same TLS settings as src/db.ts.
const url = new URL(
  process.env.DATABASE_URL ?? "postgres://localhost:5432/postgres",
);

export default defineConfig({
  dialect: "postgresql",
  schema: "./src/schema.ts",
  out: "./drizzle",
  schemaFilter: ["habit_tracker"],
  dbCredentials: {
    host: url.hostname,
    port: Number(url.port || 5432),
    user: decodeURIComponent(url.username),
    password: decodeURIComponent(url.password),
    database: url.pathname.slice(1) || "postgres",
    ssl: tlsOptions(url.href, process.env.PGSSLROOTCERT),
  },
});
