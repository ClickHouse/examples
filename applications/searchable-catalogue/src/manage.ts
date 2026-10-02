import { Migrator } from 'kysely/migration';
import { database } from './database.js';
import { initial } from './migrations.js';
const db = database();
try {
  if (process.env.PGUSER !== 'catalogue_migrator') throw new Error('Use catalogue_migrator for migrations');
  const migrator = new Migrator({ db, migrationTableSchema: 'catalogue',
    provider: { async getMigrations() { return { '001_products': initial }; } } });
  const direction = process.argv[2] ?? 'up';
  if (!['up', 'down'].includes(direction)) throw new Error('Usage: npm run migrate -- up|down');
  const result = direction === 'down' ? await migrator.migrateDown() : await migrator.migrateToLatest();
  for (const item of result.results ?? []) console.log(`${item.migrationName}: ${item.status}`);
  if (result.error) throw result.error;
} finally { await db.destroy(); }
