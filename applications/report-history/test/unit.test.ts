import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { generateReport } from '../src/generate.ts';
import { chunks, isTransient, prepareReport, withRetry, type ReportInput } from '../src/report.ts';

const input: ReportInput = { tenant_id: 'test', completed_at: '2026-08-01T12:00:00.000Z',
  report_type: 'sales', source_uri: 'file:///source.csv', artifact_uri: 'file:///report.json',
  rows: [{ region: 'eu', category: 'software', revenue_cents: 1200, units: 2 }] };

test('CSV input becomes a distinct Markdown artifact and validated analytical rows', () => {
  const dir = mkdtempSync(join(tmpdir(), 'report-history-test-'));
  const source = join(dir, 'sales.csv');
  const artifact = join(dir, 'sales.md');
  writeFileSync(source, 'region,category,revenue_cents,units\n"Western, Europe",software,1200,2\n');
  const report = generateReport(source, artifact, input);
  assert.equal(report.rows[0]?.region, 'Western, Europe');
  assert.equal(report.rows[0]?.revenue_cents, 1200);
  assert.notEqual(report.source_uri, report.artifact_uri);
  assert.match(readFileSync(artifact, 'utf8'), /Revenue: 1200 cents/);
  writeFileSync(source, 'region,category,revenue_cents,units\neu,software,,2\n');
  assert.throws(() => generateReport(source, artifact, input), /integer values/);
});

test('identity and retry batches are deterministic; changed data produces a new run', () => {
  assert.deepEqual(prepareReport(input), prepareReport(structuredClone(input)));
  assert.notEqual(prepareReport(input).run.run_id,
    prepareReport({ ...input, rows: [{ ...input.rows[0]!, revenue_cents: 1300 }] }).run.run_id);
  assert.deepEqual(chunks([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]]);
});
test('invalid timestamps and money are rejected before any insert', () => {
  assert.throws(() => prepareReport({ ...input, completed_at: 'today' }));
  assert.throws(() => prepareReport({ ...input, rows: [{ ...input.rows[0]!, revenue_cents: 1.23 }] }));
});
test('money summaries remain exact despite a large intermediate sum and refund', () => {
  const report = prepareReport({ ...input, rows: [Number.MAX_SAFE_INTEGER, 2, -2]
    .map((revenue_cents) => ({ ...input.rows[0]!, revenue_cents })) });
  assert.equal(JSON.parse(report.run.summary_json).revenue_cents, Number.MAX_SAFE_INTEGER);
});
test('the pinned ClickHouse client timeout is retryable, unrelated plain errors are not', async () => {
  assert.equal(isTransient(new Error('Timeout error.')), true);
  assert.equal(isTransient(new Error('Invalid timeout configuration')), false);
  let attempts = 0;
  await withRetry(async () => { if (++attempts === 1) throw new Error('Timeout error.'); }, { sleep: async () => {} });
  assert.equal(attempts, 2);
});
test('bounded retries recover transient failures but do not retry SQL/auth failures', async () => {
  let attempts = 0;
  assert.equal(await withRetry(async () => {
    if (++attempts < 3) throw Object.assign(new Error('connection lost'), { code: 'ECONNRESET' });
    return 'ok';
  }, { sleep: async () => {} }), 'ok');
  assert.equal(attempts, 3);
  attempts = 0;
  await assert.rejects(withRetry(async () => {
    attempts++; throw Object.assign(new Error('bad SQL'), { code: '62' });
  }, { sleep: async () => {} }));
  assert.equal(attempts, 1);
  attempts = 0;
  await assert.rejects(withRetry(async () => {
    attempts++; throw Object.assign(new Error('offline'), { code: 'ECONNRESET' });
  }, { attempts: 3, sleep: async () => {} }));
  assert.equal(attempts, 3);
});
