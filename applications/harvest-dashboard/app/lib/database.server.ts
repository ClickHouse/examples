import { readFileSync } from 'node:fs';
import { Pool, type PoolConfig } from 'pg';

export function databaseConfig(env: NodeJS.ProcessEnv = process.env): PoolConfig {
  if (!env.DATABASE_URL || !env.DATABASE_CA_PATH) throw new Error('DATABASE_URL and DATABASE_CA_PATH are required.');
  const url = new URL(env.DATABASE_URL);
  if (!['postgres:', 'postgresql:'].includes(url.protocol) || url.search || url.hash) throw new Error('Use a plain Postgres URL without query parameters.');
  if (env.NODE_TLS_REJECT_UNAUTHORIZED === '0') throw new Error('TLS verification must remain enabled.');
  return { connectionString: env.DATABASE_URL,
    ssl: { ca: readFileSync(env.DATABASE_CA_PATH, 'utf8'), rejectUnauthorized: true, servername: url.hostname },
    max: 5, connectionTimeoutMillis: 10_000, idleTimeoutMillis: 30_000,
    options: '-c search_path=harvest,pg_catalog -c statement_timeout=10000',
    application_name: 'harvest-dashboard',
  };
}
let singleton: Pool | undefined;
export function database(): Pool {
  if (!singleton) {
    singleton = new Pool(databaseConfig());
    singleton.on('error', () => console.error('An idle database connection failed.'));
  }
  return singleton;
}
export async function closeDatabase() { await singleton?.end(); singleton = undefined; }
