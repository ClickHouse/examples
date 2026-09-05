import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { connect, ReportStore } from './store.ts';
import { generateReport } from './generate.ts';

const client = connect();
const store = new ReportStore(client);
const tenant = 'report-history-demo';
try {
  const command = process.argv[2];
  if (command === 'demo') {
    mkdirSync('.local', { recursive: true });
    for (let index = 0; index < 3; index++) {
      const sourcePath = resolve(`.local/sales-source-${index}.csv`);
      const artifactPath = resolve(`.local/sales-report-${index}.md`);
      // Generate a bounded CSV input, then READ it through the actual report generator.
      const csvRows = Array.from({ length: 2000 }, (_, row) => [ ['eu', 'us'][row % 2]!,
        ['software', 'services', 'hardware'][row % 3]!, (index + 1) * 100 + row, 1 + row % 5 ].join(','));
      writeFileSync(sourcePath, 'region,category,revenue_cents,units\n' + csvRows.join('\n') + '\n');
      const input = generateReport(sourcePath, artifactPath, { tenant_id: tenant,
        completed_at: `2026-08-0${index + 1}T12:00:00.000Z`, report_type: 'sales-summary' });
      const runId = await store.publish(input);
      // Replaying the exact report is safe: stable run ID, batches, and deduplicated reads.
      await store.publish(input);
      console.log(`Published report ${runId}: ${input.rows.length} rows (including a deliberate retry)`);
    }
    console.log(JSON.stringify(await store.history(tenant), null, 2));
    console.log(JSON.stringify(await store.analytics(tenant), null, 2));
  } else if (command === 'history') {
    console.log(JSON.stringify(await store.history(tenant), null, 2));
  } else if (command === 'analytics') {
    console.log(JSON.stringify(await store.analytics(tenant), null, 2));
  } else throw new Error('Usage: npm run demo|history|analytics');
} finally {
  await client.close();
}
