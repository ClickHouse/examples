import { readFileSync } from 'node:fs';
import type { DataSourceOptions } from 'typeorm';
import { AccountSchema, ShipmentSchema, EventSchema } from './entities.js';
import { Initial1700000000000 } from '../migrations/initial.js';

export function required(name: string): string {
  const value = process.env[name];
  if (!value?.trim()) throw new Error(`Missing configuration: ${name}`);
  return value;
}
export function dbOptions(migration = false): DataSourceOptions {
  const role = migration ? 'shipments_migrator' : 'shipments_app';
  if (required('PGUSER') !== role) throw new Error(`This command requires ${role}`);
  const port = Number(process.env.PGPORT ?? 5432);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid Postgres port');
  return {
    type: 'postgres', host: required('PGHOST'), port, database: required('PGDATABASE'),
    username: role, password: required('PGPASSWORD'), schema: 'shipments',
    ssl: { ca: readFileSync(required('PGSSLROOTCERT'), 'utf8'), rejectUnauthorized: true },
    synchronize: false, migrationsRun: false, logging: false,
    entities: [AccountSchema, ShipmentSchema, EventSchema], migrations: [Initial1700000000000],
    migrationsTableName: 'schema_migrations', migrationsTransactionMode: 'all',
    extra: {
      max: 5, connectionTimeoutMillis: 10_000, idleTimeoutMillis: 30_000,
      query_timeout: 25_000,
      options: '-c search_path=shipments -c timezone=UTC -c statement_timeout=20000' +
        (migration ? ' -c role=shipments_owner' : ''),
    },
  };
}
export function analyticalUrl(value: string): string {
  const url = new URL(value);
  if (url.protocol !== 'https:' || !url.hostname || url.username || url.password ||
      url.search || url.hash || !['', '/'].includes(url.pathname)) throw new Error('Invalid analytical HTTPS URL');
  return value;
}
