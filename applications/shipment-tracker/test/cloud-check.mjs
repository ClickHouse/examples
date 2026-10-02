// Run manually against the seeded Cloud fixture; never runs in credential-free CI.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { setTimeout as pause } from 'node:timers/promises';
import pg from 'pg';
const accountA = '00000000-0000-4000-8000-000000000001';
const accountB = '00000000-0000-4000-8000-000000000002';
const tokens = JSON.parse(process.env.ACCOUNT_TOKENS);
const base = process.env.TEST_URL ?? 'http://127.0.0.1:3000';
const ship = (account, n) => `${account === accountA ? 'a' : 'b'}0000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
async function http(account, path, body, expected = 200) {
  const response = await fetch(base + path, {
    method: body ? 'POST' : 'GET',
    headers: { Authorization: `Bearer ${tokens[account]}`, ...(body ? { 'Content-Type': 'application/json' } : {}) },
    body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(35_000),
  });
  const data = await response.json();
  if (expected !== null) assert.equal(response.status, expected, JSON.stringify(data));
  return { status: response.status, data };
}
const transition = (account, n, requestId, expectedRevision, toStatus, expected = 201) =>
  http(account, `/shipments/${ship(account, n)}/transitions`, { requestId, expectedRevision, toStatus }, expected);
const pool = new pg.Pool({
  host: process.env.PGHOST, port: Number(process.env.PGPORT), database: process.env.PGDATABASE,
  user: 'shipments_migrator', password: process.env.TEST_MIGRATOR_PASSWORD,
  ssl: { ca: readFileSync(process.env.PGSSLROOTCERT, 'utf8'), rejectUnauthorized: true },
  max: 2, connectionTimeoutMillis: 10_000, query_timeout: 25_000,
  options: '-c role=shipments_owner -c timezone=UTC -c statement_timeout=20000',
});
async function snapshot() {
  await transition(accountA, 1, 'snapshot-a-dispatch', 0, 'dispatched');
  await pause(30);
  const delivered = (await transition(accountA, 1, 'snapshot-a-deliver', 1, 'delivered')).data;
  assert.equal(BigInt(delivered.durationMs), BigInt(Date.parse(delivered.eventAt) - Date.parse(delivered.dispatchedAt)));
  await transition(accountB, 1, 'snapshot-b-dispatch', 0, 'dispatched');
  const { rows } = await pool.query('SELECT count(*)::int AS count FROM shipments.events');
  assert.equal(rows[0].count, 3);
  console.log('Initial snapshot fixture: 3 accepted events, terminal duration matches stored millisecond timestamps');
}
async function core() {
  const race = await Promise.all([
    transition(accountA, 2, 'race-dispatch', 0, 'dispatched', null),
    transition(accountA, 2, 'race-cancel', 0, 'cancelled', null),
  ]);
  assert.deepEqual(race.map(r => r.status).sort(), [201, 409]);
  assert.equal((await http(accountA, `/shipments/${ship(accountA, 2)}`)).data.revision, 1);
  assert.equal((await http(accountA, `/shipments/${ship(accountA, 2)}/events`)).data.items.length, 1);
  console.log('Two simultaneous transitions from revision 0: one 201, one 409, one state/event advance');
  const duplicates = await Promise.all(Array.from({ length: 10 }, () => transition(accountA, 3, 'same-id', 0, 'dispatched', null)));
  assert.deepEqual(duplicates.map(r => r.status).sort(), [...Array(9).fill(200), 201]);
  assert.equal(new Set(duplicates.map(r => r.data.id)).size, 1);
  assert.equal((await http(accountA, `/shipments/${ship(accountA, 3)}/events`)).data.items.length, 1);
  await pause(30);
  await transition(accountA, 3, 'same-id-deliver', 1, 'delivered');
  const retry = await transition(accountA, 3, 'same-id', 0, 'dispatched', 200);
  assert.deepEqual(retry.data, duplicates[0].data);
  const uppercase = await http(accountA, `/shipments/${ship(accountA, 3).toUpperCase()}/transitions`,
    { requestId: 'same-id', expectedRevision: 0, toStatus: 'dispatched' });
  assert.deepEqual(uppercase.data, retry.data);
  await transition(accountA, 3, 'same-id', 0, 'cancelled', 409);
  await transition(accountA, 3, 'same-id', 1, 'dispatched', 409);
  await transition(accountA, 4, 'same-id', 0, 'dispatched', 409);
  console.log('10 simultaneous matching requests: one 201 + nine 200; retained replay survives later delivery, uppercase UUID path, and restart fixture; changed payload/revision/shipment conflicts');
  await transition(accountA, 4, 'cancel-created', 0, 'cancelled');
  await transition(accountA, 4, 'invalid-terminal', 1, 'dispatched', 409);
  await transition(accountA, 6, 'skip-dispatch', 0, 'delivered', 409);
  await http(accountB, `/shipments/${ship(accountA, 1)}`, undefined, 404);
  await http(accountB, `/shipments/${ship(accountA, 1)}/events`, undefined, 404);
  await http(accountB, `/shipments/${ship(accountA, 1)}/transitions`, { requestId: 'cross-account', expectedRevision: 2, toStatus: 'cancelled' }, 404);
  // Trusted account identity cannot be supplied by a caller.
  await http(accountA, `/shipments/${ship(accountA, 6)}/transitions`,
    { requestId: 'forged', expectedRevision: 0, toStatus: 'dispatched', accountId: accountB }, 400);
  for (const body of [
    { requestId: 'newline\n', expectedRevision: 0, toStatus: 'dispatched' },
    { requestId: 'nul\0', expectedRevision: 0, toStatus: 'dispatched' },
    { requestId: 'string-revision', expectedRevision: '0', toStatus: 'dispatched' },
    { requestId: 'negative', expectedRevision: -1, toStatus: 'dispatched' },
  ]) await http(accountA, `/shipments/${ship(accountA, 6)}/transitions`, body, 400);
  for (const path of ['/shipments?limit=51', '/shipments?after=bad', '/shipments/not-a-uuid', '/reports?from=2026-02-30', '/reports?from=1900-01-01']) {
    await http(accountA, path, undefined, 400);
  }
  await http(accountA, `/shipments/${ship(accountA, 6)}/transitions`, { requestId: 'oversized', padding: 'x'.repeat(5000) }, 413);
  const unauthenticated = await fetch(base + '/shipments', { headers: { Authorization: 'Bearer invalid' } });
  assert.equal(unauthenticated.status, 401);
  const listed = [];
  let after = '';
  do {
    const page = (await http(accountA, `/shipments?limit=2${after ? `&after=${after}` : ''}`)).data;
    assert.ok(page.items.length <= 2);
    listed.push(...page.items.map(s => s.id));
    after = page.nextAfter;
  } while (after);
  assert.deepEqual(listed, Array.from({ length: 6 }, (_, i) => ship(accountA, i + 1)));
  const firstHistory = (await http(accountA, `/shipments/${ship(accountA, 3)}/events?limit=1`)).data;
  assert.equal(firstHistory.nextRevision, 1);
  const secondHistory = (await http(accountA, `/shipments/${ship(accountA, 3)}/events?limit=1&afterRevision=1`)).data;
  assert.equal(secondHistory.items[0].revision, 2);
  assert.equal(secondHistory.nextRevision, null);
  console.log('Lifecycle, stale revisions, account isolation, authentication, strict inputs, 4 KiB body, UUID keyset and revision history controls passed');
  const before = (await http(accountA, `/shipments/${ship(accountA, 5)}`)).data;
  await pool.query(`CREATE FUNCTION shipments.reject_fixture_event() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN IF NEW.request_id = 'force-rollback' THEN RAISE EXCEPTION 'Controlled acceptance insert failure'; END IF; RETURN NEW; END $$;
    CREATE TRIGGER reject_fixture_event BEFORE INSERT ON shipments.events FOR EACH ROW EXECUTE FUNCTION shipments.reject_fixture_event()`);
  try {
    await transition(accountA, 5, 'force-rollback', 0, 'dispatched', 503);
    assert.deepEqual((await http(accountA, `/shipments/${ship(accountA, 5)}`)).data, before);
    assert.equal((await http(accountA, `/shipments/${ship(accountA, 5)}/events`)).data.items.length, 0);
    console.log('Forced failure after shipment UPDATE: state, revision, dispatch timestamp and event insertion all rolled back');
  } finally {
    await pool.query('DROP TRIGGER reject_fixture_event ON shipments.events; DROP FUNCTION shipments.reject_fixture_event()');
  }
}
async function equality() {
  for (const account of [accountA, accountB]) {
    const { rows } = await pool.query(`SELECT event_day::text AS "eventDay", service_level AS "serviceLevel", to_status AS "toStatus",
      count(*)::text AS events, count(*) FILTER (WHERE to_status='delivered')::text AS "deliveredCount",
      coalesce(sum(duration_ms) FILTER (WHERE to_status='delivered'),0)::text AS "totalDurationMs",
      coalesce(max(duration_ms) FILTER (WHERE to_status='delivered'),0)::text AS "maxDurationMs"
      FROM shipments.events WHERE account_id=$1 AND event_day BETWEEN (current_timestamp AT TIME ZONE 'UTC')::date-6 AND (current_timestamp AT TIME ZONE 'UTC')::date
      GROUP BY event_day,service_level,to_status ORDER BY event_day,service_level,to_status`, [account]);
    let last;
    const deadline = Date.now() + 180_000;
    do {
      last = await http(account, '/reports', undefined, null);
      if (last.status === 200 && JSON.stringify(last.data.rows) === JSON.stringify(rows)) break;
      await pause(3000);
    } while (Date.now() < deadline);
    assert.equal(last.status, 200);
    assert.deepEqual(last.data.rows, rows);
    for (const row of last.data.rows) for (const key of ['events', 'deliveredCount', 'totalDurationMs', 'maxDurationMs']) assert.equal(typeof row[key], 'string');
    console.log(`Exact account ${account.at(-1)} equality: ${rows.length} daily groups; counts, delivered count, total/max duration; all aggregates are strings`);
  }
}
try {
  if (process.argv[2] === 'snapshot') await snapshot();
  else if (process.argv[2] === 'core') await core();
  else if (process.argv[2] === 'equality') await equality();
  else throw new Error('Use snapshot, core or equality');
} finally { await pool.end(); }
