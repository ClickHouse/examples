import { SQL } from "bun";
import { drizzle } from "drizzle-orm/bun-sql";
export async function connectDatabase(
  urlText = process.env.DATABASE_URL,
  caPath = process.env.PG_CA_CERT_PATH,
) {
  if (!urlText) throw new Error("DATABASE_URL is required.");
  const url = new URL(urlText);
  if (
    !["postgres:", "postgresql:"].includes(url.protocol) ||
    url.search ||
    url.hash
  )
    throw new Error("Use a plain Postgres URL without query parameters.");
  const local = process.env.DATABASE_LOCAL === "true";
  if (local && !["localhost", "127.0.0.1", "[::1]"].includes(url.hostname))
    throw new Error("DATABASE_LOCAL requires a loopback host.");
  if (!local && !caPath)
    throw new Error("PG_CA_CERT_PATH is required for verified TLS.");
  url.searchParams.set("sslmode", local ? "disable" : "verify-full");
  const ca = local ? undefined : await Bun.file(caPath!).text();
  const client = new SQL(url, {
    max: 5,
    connectionTimeout: 10,
    idleTimeout: 30,
    maxLifetime: 1800,
    ...(local
      ? {}
      : { tls: { ca, serverName: url.hostname, rejectUnauthorized: true } }),
  });
  try {
    await client`SELECT 1`;
  } catch (error) {
    await client.close({ timeout: 0 });
    throw error;
  }
  return { client, db: drizzle({ client }) };
}
export type Database = Awaited<ReturnType<typeof connectDatabase>>["db"];
