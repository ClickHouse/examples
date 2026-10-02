import 'reflect-metadata';
import { DataSource } from 'typeorm';
import { dbOptions } from './config.js';
import { AccountSchema, ShipmentSchema } from './entities.js';

async function main(): Promise<void> {
  const source = await new DataSource(dbOptions(true)).initialize();
  try {
    switch (process.argv[2]) {
      case 'up': console.log('Applied migrations:', (await source.runMigrations()).length); break;
      case 'down': await source.undoLastMigration(); console.log('Reverted latest migration'); break;
      case 'seed':
        await source.transaction(async manager => {
          const accounts = [
            { id: '00000000-0000-4000-8000-000000000001', name: 'North warehouse' },
            { id: '00000000-0000-4000-8000-000000000002', name: 'South warehouse' },
          ];
          await manager.getRepository(AccountSchema).createQueryBuilder().insert().values(accounts).orIgnore().execute();
          const now = new Date();
          for (const [index, account] of accounts.entries()) {
            for (let number = 1; number <= (index === 0 ? 6 : 3); number++) {
              await manager.getRepository(ShipmentSchema).createQueryBuilder().insert().values({
                id: `${index === 0 ? 'a' : 'b'}0000000-0000-4000-8000-${String(number).padStart(12, '0')}`,
                accountId: account.id, serviceLevel: number % 2 === 0 ? 'express' : 'standard',
                status: 'created', revision: 0, dispatchedAt: null, createdAt: now, updatedAt: now,
              }).orIgnore().execute();
            }
          }
        });
        console.log('Seeded two accounts and nine shipments; existing state retained');
        break;
      default: throw new Error('Expected up, down or seed');
    }
  } finally { await source.destroy(); }
}
main().catch(() => { console.error('Schema command failed; inspect credentials, TLS, role and migration state'); process.exitCode = 1; });
