import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { connect, ReportStore } from '../src/store.ts';
import { prepareReport, type ReportInput } from '../src/report.ts';

test('Cloud: replay, interrupted publication, completeness, analytics, status and least privilege', async () => {
  const client = connect();
  const store = new ReportStore(client);
  const tenant = `integration-${randomUUID()}`;
  const input: ReportInput = { tenant_id: tenant, completed_at: '2026-08-01T12:00:00.000Z',
    report_type: 'sales', source_uri: 'file:///fixture.csv', artifact_uri: 'file:///fixture.json',
    rows: Array.from({ length: 2001 }, (_, index) => ({ region: 'eu', category: 'software',
      revenue_cents: 100, units: 2 })) };
  try {
    const prepared = prepareReport(input);
    // Simulate process death after result inserts, before publishing the marker.
    await store.writeResults(prepared);
    assert.equal((await store.history(tenant)).length, 0);
    assert.equal((await store.analytics(tenant)).length, 0);
    await store.publish(input);
    await store.publish(input);
    assert.equal((await store.history(tenant)).length, 1);
    assert.equal((await store.report(tenant, prepared.run.run_id)).length, 2001);
    let analytics = await store.analytics(tenant);
    assert.equal(analytics[0]?.revenue_cents, '200100');
    assert.equal(analytics[0]?.result_rows, '2001');
    assert.equal((await store.history('different-tenant')).length, 0);

    // Force physical duplicates without insert deduplication: logical reads remain correct.
    await client.insert({ table: 'report_results', values: prepared.results, format: 'JSONEachRow',
      clickhouse_settings: { insert_deduplicate: 0 } });
    assert.equal((await store.report(tenant, prepared.run.run_id)).length, 2001);

    const second = { ...input, completed_at: '2026-08-01T13:00:00.000Z', rows: [input.rows[0]!] };
    const secondPrepared = prepareReport(second);
    // Simulate a malformed/out-of-order producer: a marker alone must not advertise missing results.
    await store.writeCompletion(secondPrepared);
    assert.equal((await store.history(tenant)).length, 1);
    await store.publish(second);
    analytics = await store.analytics(tenant);
    assert.equal(analytics[0]?.revenue_cents, '200200');
    assert.equal(analytics[0]?.reports, '2');
    assert.equal((await store.history(tenant)).length, 2);

    await store.publish({ ...input, report_type: 'empty', rows: [] });
    assert.equal((await store.history(tenant)).length, 3);

    await store.status(tenant, prepared.run.run_id, 3, 'completed', input.completed_at);
    await store.status(tenant, prepared.run.run_id, 2, 'running', input.completed_at);
    const statuses = await store.currentStatus(tenant, prepared.run.run_id);
    assert.equal(statuses[0]?.status, 'completed');
    assert.equal(statuses[0]?.version, '3');

    await assert.rejects(client.command({ query: 'CREATE TABLE report_history.forbidden (id UInt8) ENGINE = Memory' }),
      (error: unknown) => String((error as { code?: string }).code) === '497');
    const version = await client.query({ query: 'SELECT version() AS version', format: 'JSONEachRow' });
    console.log('Verified Cloud version:', await version.json());
  } finally { await client.close(); }
});
