import { readFileSync } from 'node:fs';
import { checkServerIdentity } from 'node:tls';
import pg from 'pg';
import { Kysely, PostgresDialect } from 'kysely';

export interface Product {
  id: string; sku: string; name: string; description: string;
  category: string; price_pence: number; active: boolean;
}
export interface Database { products: Product }
function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}
export function poolOptions(user = required('PGUSER'), password = required('PGPASSWORD')): pg.PoolConfig {
  const host = required('PGHOST');
  const port = Number(process.env.PGPORT ?? '5432');
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid PGPORT');
  return {
    host, port, database: required('PGDATABASE'), user, password,
    max: 5, connectionTimeoutMillis: 10000, idleTimeoutMillis: 30000,
    statement_timeout: 5000, application_name: 'searchable-catalogue',
    ...(user === 'catalogue_migrator' ? { options: '-c role=catalogue_owner' } : {}),
    ssl: {
      ca: readFileSync(required('PGSSLROOTCERT'), 'utf8'),
      rejectUnauthorized: true, servername: host,
      // Bind verification explicitly to the configured endpoint, including IPs.
      checkServerIdentity: (_servername, cert) => checkServerIdentity(host, cert),
    },
  };
}
export function database(user?: string, password?: string): Kysely<Database> {
  const pool = new pg.Pool(poolOptions(user, password));
  pool.on('error', () => console.error('Idle database connection failed'));
  return new Kysely<Database>({ dialect: new PostgresDialect({ pool }) }).withSchema('catalogue');
}
