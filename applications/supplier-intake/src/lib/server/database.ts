import { readFileSync } from 'node:fs';
import { Pool } from 'pg';
let pool: Pool | undefined;
export function databaseConfig() {
  const connectionString = process.env.DATABASE_URL;
  const caPath = process.env.DATABASE_CA_PATH;
  if (!connectionString || !caPath)
    throw new Error('DATABASE_URL and DATABASE_CA_PATH are required.');
  const url = new URL(connectionString);
  if (
    !['postgresql:', 'postgres:'].includes(url.protocol) ||
    url.search ||
    url.hash ||
    process.env.NODE_TLS_REJECT_UNAUTHORIZED === '0'
  )
    throw new Error('Use a direct Postgres URL without SSL query parameters.');
  return {
    connectionString,
    max: 5,
    connectionTimeoutMillis: 10_000,
    query_timeout: 15_000,
    ssl: {
      ca: readFileSync(caPath, 'utf8'),
      rejectUnauthorized: true,
      servername: url.hostname,
    },
  };
}
export function database() {
  return (pool ??= new Pool(databaseConfig()));
}
export async function closeDatabase() {
  await pool?.end();
  pool = undefined;
}
