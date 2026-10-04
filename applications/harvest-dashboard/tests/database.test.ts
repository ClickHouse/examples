import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { lookup } from 'node:dns/promises';
import { Pool } from 'pg';
import { database, databaseConfig, closeDatabase } from '../app/lib/database.server';
import { createHarvest, updateHarvest, deleteHarvest, loadDashboard, RevisionConflict } from '../app/lib/harvest.server';

const input = { cropId: '10000000-0000-4000-8000-000000000001', bedId: '20000000-0000-4000-8000-000000000001', harvestedOn: '2026-10-04', grams: 400, note: 'integration fixture' };
test('configured Postgres fixture: mutations, stale edits, Monday buckets and role/TLS controls', async () => {
  const ids: string[] = [];
  try {
    const identity = await database().query('SELECT current_user, version() AS version');
    assert.equal(identity.rows[0].current_user, 'harvest_app');
    console.log(JSON.stringify({ currentUser: identity.rows[0].current_user, postgres: identity.rows[0].version }));
    const before = await loadDashboard({ from: '2026-10-04', to: '2026-10-05', cropId: input.cropId });
    const first = await createHarvest(input); ids.push(first);
    const second = await createHarvest({ ...input, harvestedOn: '2026-10-05', grams: 600 }); ids.push(second);
    const after = await loadDashboard({ from: '2026-10-04', to: '2026-10-05', cropId: input.cropId });
    assert.equal(after.summary.grams - before.summary.grams, 1000);
    assert.equal(after.summary.count - before.summary.count, 2);
    assert.equal(after.cropTotals.reduce((sum, v) => sum + v.grams, 0), after.summary.grams);
    assert.equal(after.weekly.reduce((sum, v) => sum + v.grams, 0), after.summary.grams);
    assert.equal(after.weekly.find((v) => v.week === '2026-09-28')!.grams - (before.weekly.find((v) => v.week === '2026-09-28')?.grams ?? 0), 400);
    assert.equal(after.weekly.find((v) => v.week === '2026-10-05')!.grams - (before.weekly.find((v) => v.week === '2026-10-05')?.grams ?? 0), 600);

    const competing = await Promise.allSettled([
      updateHarvest(first, 1, { ...input, grams: 450 }),
      updateHarvest(first, 1, { ...input, grams: 500 }),
    ]);
    assert.equal(competing.filter((v) => v.status === 'fulfilled').length, 1);
    const rejection = competing.find((v) => v.status === 'rejected') as PromiseRejectedResult;
    assert.ok(rejection.reason instanceof RevisionConflict);
    await assert.rejects(deleteHarvest(first, 1), RevisionConflict);
    await deleteHarvest(first, 2);
    await assert.rejects(updateHarvest(first, 2, input), RevisionConflict);
    await assert.rejects(database().query('INSERT INTO harvest.entries (crop_id,bed_id,harvested_on,grams) VALUES ($1,$2,$3,-1)', [input.cropId, input.bedId, input.harvestedOn]), (error: any) => error.code === '23514');
    for (const statement of [
      'CREATE TABLE harvest.forbidden (id integer)',
      'ALTER TABLE harvest.entries ADD COLUMN forbidden text',
      "INSERT INTO harvest.crops (id,name) VALUES (gen_random_uuid(),'forbidden')",
    ]) await assert.rejects(database().query(statement), (error: any) => error.code === '42501');

    const config = databaseConfig();
    // pg supplies SNI from a DNS connection host, overriding ssl.servername.
    // Connect to the same resolved IPv4 endpoint so the deliberately wrong
    // expected TLS name reaches Node's actual certificate verification.
    const directIpUrl = new URL(process.env.DATABASE_URL!);
    directIpUrl.hostname = (await lookup(directIpUrl.hostname, { family: 4 })).address;
    const wrongHostname = new Pool({ ...config, connectionString: directIpUrl.toString(), max: 1, ssl: { ...(config.ssl as object), servername: 'wrong-host.invalid' } });
    try { await assert.rejects(wrongHostname.query('SELECT 1'), (error: any) => error.code === 'ERR_TLS_CERT_ALTNAME_INVALID'); }
    finally { await wrongHostname.end(); }
    const directory = mkdtempSync(join(tmpdir(), 'harvest-ca-'));
    try {
      execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', join(directory, 'key.pem'), '-out', join(directory, 'ca.pem'), '-days', '1', '-subj', '/CN=unrelated-test-root'], { stdio: 'ignore' });
      const wrongCa = new Pool({ ...config, max: 1, ssl: { ...(config.ssl as object), ca: readFileSync(join(directory, 'ca.pem'), 'utf8') } });
      try { await assert.rejects(wrongCa.query('SELECT 1'), (error: any) => ['UNABLE_TO_VERIFY_LEAF_SIGNATURE','UNABLE_TO_GET_ISSUER_CERT_LOCALLY','SELF_SIGNED_CERT_IN_CHAIN','DEPTH_ZERO_SELF_SIGNED_CERT'].includes(error.code)); }
      finally { await wrongCa.end(); }
    } finally { rmSync(directory, { recursive: true, force: true }); }
    console.log('Verified create/edit/delete, stale versions, SQL chart totals, Monday date buckets, runtime role, wrong CA and wrong hostname.');
  } finally {
    if (ids.length) await database().query('DELETE FROM harvest.entries WHERE id=ANY($1::uuid[])', [ids]);
    await closeDatabase();
  }
});
