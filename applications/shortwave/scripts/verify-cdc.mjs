#!/usr/bin/env node
// Run with --env-file=.deployment/runtime.env. Only synthetic fixture rows are
// changed; ClickPipes remains the sole writer of the CDC destination table.
import { randomBytes, randomUUID, createHash } from 'node:crypto';
import { readFile, writeFile, mkdir, open, unlink } from 'node:fs/promises';
import { resolve, relative, sep } from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { Client } from 'pg';
import { createClient, ClickHouseLogLevel } from '@clickhouse/client';

process.umask(0o077);
const directory = resolve('.deployment');
const cleanupMode = process.argv[2] === '--cleanup';
const snapshotMode = process.argv[2] === '--await-snapshot';
if (process.argv.length > 2 && !(cleanupMode && process.argv[3] && process.argv.length === 4) && !(snapshotMode && process.argv.length === 3)) {
  console.error('Usage: node --env-file=.deployment/runtime.env scripts/verify-cdc.mjs [--cleanup .deployment/RECEIPT.json | --await-snapshot]');
  process.exit(1);
}
let receiptPath;
let receipt;
let postgres;
let clickhouse;
let sourceFingerprint;
let snapshotLock;

async function save() {
  await writeFile(receiptPath, `${JSON.stringify(receipt, null, 2)}\n`, { mode: 0o600 });
}
async function cleanup() {
  if (!postgres || !receipt) return;
  if (receipt.sourceFingerprint !== sourceFingerprint) throw new Error('Runtime environment does not match the recorded source database');
  const owned = (await postgres.query('SELECT id FROM accounts WHERE id = $1 AND clerk_user_id = $2', [receipt.accountId, receipt.marker])).rows.length;
  if (owned) {
    await postgres.query('BEGIN');
    try {
      await postgres.query('DELETE FROM links WHERE id = $1 AND account_id = $2', [receipt.linkId, receipt.accountId]);
      await postgres.query('DELETE FROM accounts WHERE id = $1 AND clerk_user_id = $2', [receipt.accountId, receipt.marker]);
      await postgres.query('COMMIT');
    } catch (error) { await postgres.query('ROLLBACK'); throw error; }
  }
  receipt.sourceCleanedAt = new Date().toISOString();
  await save();
}

async function awaitSnapshot() {
  // The operator runs clickhousectl resync separately, after this fixture is ready.
  const database = process.env.CLICKHOUSE_CDC_DATABASE;
  const tableUuid = async () => {
    const result = await clickhouse.query({ query: 'SELECT uuid FROM system.tables WHERE database = {database:String} AND name = {table:String}', query_params: { database, table: 'cdc_links' }, format: 'JSONEachRow' });
    const rows = await result.json();
    if (rows.length !== 1) throw new Error('CDC destination table is missing');
    return rows[0].uuid;
  };
  const previousUuid = await tableUuid();
  receipt.snapshotWaitStartedAt = new Date().toISOString();
  await save();
  console.log('Snapshot fixture ready. Run the documented clickhousectl resync command for this disposable deployment in another terminal.');
  // A row in the old destination could be CDC from before resync. Require the
  // documented atomic swap of the snapshot table (a different table UUID)
  // before claiming that the populated snapshot was verified.
  const until = Date.now() + 600_000;
  while (Date.now() < until) {
    if (await tableUuid() !== previousUuid) {
      receipt.passed.push('Snapshot destination atomically replaced');
      await save();
      console.log('Snapshot destination atomically replaced: passed');
      return;
    }
    await sleep(5_000);
  }
  throw new Error('Snapshot destination did not swap within ten minutes');
}
async function awaitCdc(label, matches) {
  const database = process.env.CLICKHOUSE_CDC_DATABASE;
  if (!database || !/^[a-z_][a-z_0-9]*$/i.test(database)) throw new Error('Configure CLICKHOUSE_CDC_DATABASE');
  const until = Date.now() + 180_000;
  while (Date.now() < until) {
    const result = await clickhouse.query({
      query: `SELECT account_id, revision, title, destination, resolved_url, tags, _peerdb_is_deleted FROM ${database}.cdc_links FINAL WHERE id = {id:UUID}`,
      query_params: { id: receipt.linkId }, format: 'JSONEachRow',
    });
    const rows = await result.json();
    if (rows.length === 1 && matches(rows[0])) {
      receipt.passed.push(label);
      await save();
      console.log(`${label}: passed`);
      return;
    }
    await sleep(5_000);
  }
  throw new Error(`${label} did not converge within three minutes`);
}

try {
  if (!process.env.DATABASE_URL || !process.env.PG_CA_CERT_PATH || !process.env.CLICKHOUSE_URL || !process.env.CLICKHOUSE_USERNAME || !process.env.CLICKHOUSE_PASSWORD) throw new Error('Load runtime.env before running CDC verification');
  await mkdir(directory, { recursive: true, mode: 0o700 });
  if (snapshotMode) {
    snapshotLock = await open(resolve(directory, 'cdc-snapshot.lock'), 'wx', 0o600);
    await snapshotLock.writeFile(`${process.pid}\n`);
  }
  if (cleanupMode) {
    receiptPath = resolve(process.argv[3]);
    const local = relative(directory, receiptPath);
    if (!local || local === '..' || local.startsWith(`..${sep}`)) throw new Error('Cleanup receipt must be inside .deployment');
    receipt = JSON.parse(await readFile(receiptPath, 'utf8'));
    const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;
    if (receipt.kind !== 'shortwave-cdc-verification' || !uuid.test(receipt.runId) || !uuid.test(receipt.accountId) || !uuid.test(receipt.linkId) || receipt.marker !== `__shortwave_cdc_check_${receipt.runId}`) throw new Error('Invalid CDC cleanup receipt');
  } else {
    const runId = randomUUID();
    receipt = { kind: 'shortwave-cdc-verification', runId, accountId: randomUUID(), linkId: randomUUID(), marker: `__shortwave_cdc_check_${runId}`, startedAt: new Date().toISOString(), passed: [] };
    receiptPath = resolve(directory, `cdc-${runId}.json`);
    await save();
  }
  const connection = new URL(process.env.DATABASE_URL);
  connection.search = '';
  sourceFingerprint = createHash('sha256').update(`${connection.hostname}:${connection.port || '5432'}${connection.pathname}`).digest('hex');
  if (!cleanupMode) { receipt.sourceFingerprint = sourceFingerprint; await save(); }
  else if (receipt.sourceFingerprint !== sourceFingerprint) throw new Error('Runtime environment does not match the recorded source database');
  postgres = new Client({ connectionString: connection.toString(), ssl: { ca: await readFile(process.env.PG_CA_CERT_PATH, 'utf8'), rejectUnauthorized: true }, connectionTimeoutMillis: 15_000, statement_timeout: 30_000 });
  await postgres.connect();
  if (cleanupMode) {
    await cleanup();
    console.log('Recorded CDC source fixture cleaned.');
  } else {
    clickhouse = createClient({ url: process.env.CLICKHOUSE_URL, username: process.env.CLICKHOUSE_USERNAME, password: process.env.CLICKHOUSE_PASSWORD, log: { level: ClickHouseLogLevel.OFF }, request_timeout: 30_000 });
    // High-entropy values exceed a Postgres page even after compression,
    // requiring TOAST storage. Updating other fields must preserve both URLs.
    const destination = `https://example.com/cdc-check?data=${randomBytes(16_384).toString('base64url')}`;
    await postgres.query('BEGIN');
    try {
      await postgres.query('INSERT INTO accounts(id, clerk_user_id) VALUES ($1, $2)', [receipt.accountId, receipt.marker]);
      await postgres.query('INSERT INTO links(id, account_id, slug, title, destination, resolved_url, tags) VALUES ($1, $2, $3, $4, $5, $5, $6)', [receipt.linkId, receipt.accountId, `cdc_${randomBytes(12).toString('hex')}`, 'CDC verification', destination, ['cdc-before', 'shared']]);
      await postgres.query('COMMIT');
    } catch (error) { await postgres.query('ROLLBACK'); throw error; }
    if (snapshotMode) await awaitSnapshot();
    await awaitCdc(snapshotMode ? 'Populated snapshot' : 'CDC insert', row => row.account_id === receipt.accountId && Number(row.revision) === 1 && Number(row._peerdb_is_deleted) === 0 && row.destination === destination && row.resolved_url === destination && JSON.stringify(row.tags) === JSON.stringify(['cdc-before', 'shared']));
    await postgres.query('UPDATE links SET title = $1, tags = $2, revision = revision + 1, updated_at = now() WHERE id = $3 AND account_id = $4', ['CDC verification updated', ['cdc-after', 'shared'], receipt.linkId, receipt.accountId]);
    await awaitCdc('CDC update preserves unchanged TOAST and replaces tags', row => row.account_id === receipt.accountId && Number(row.revision) === 2 && Number(row._peerdb_is_deleted) === 0 && row.title === 'CDC verification updated' && row.destination === destination && row.resolved_url === destination && JSON.stringify(row.tags) === JSON.stringify(['cdc-after', 'shared']));
    await postgres.query('DELETE FROM links WHERE id = $1 AND account_id = $2', [receipt.linkId, receipt.accountId]);
    await awaitCdc('CDC delete tombstone', row => Number(row._peerdb_is_deleted) === 1);
    await cleanup();
    receipt.completedAt = new Date().toISOString();
    await save();
    console.log('CDC verification passed; the source account and link were removed. A synthetic destination tombstone remains.');
  }
} catch (error) {
  if (receipt) { receipt.failureCode = typeof error.code === 'string' ? error.code : 'verification_failed'; await save().catch(() => {}); }
  console.error('CDC verification failed. The private receipt records the completed assertions and identifies only this fixture for cleanup.');
  try { await cleanup(); } catch { console.error('Source cleanup remains pending; run again with --cleanup and the private receipt.'); }
  process.exitCode = 1;
} finally {
  await Promise.allSettled([postgres?.end(), clickhouse?.close()]);
  if (snapshotLock) { await snapshotLock.close(); await unlink(resolve(directory, 'cdc-snapshot.lock')); }
  if (receiptPath) console.log(`Private receipt: ${receiptPath}`);
}
