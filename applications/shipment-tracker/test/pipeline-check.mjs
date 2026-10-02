// Requires private administrator test credentials. The application has neither.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { setTimeout as pause } from 'node:timers/promises';
import { createClient } from '@clickhouse/client';
import pg from 'pg';
const a = '00000000-0000-4000-8000-000000000001';
const b = '00000000-0000-4000-8000-000000000002';
const tokens = JSON.parse(process.env.ACCOUNT_TOKENS);
const admin = createClient({ url: process.env.CLICKHOUSE_URL, username: 'default',
  password: process.env.TEST_CH_ADMIN_PASSWORD, request_timeout: 10_000,
  clickhouse_settings: { max_execution_time: 5, max_rows_to_read: '1000000', max_bytes_to_read: '100000000' } });
const owner = new pg.Pool({ host: process.env.PGHOST, port: Number(process.env.PGPORT), database: process.env.PGDATABASE,
  user: 'shipments_migrator', password: process.env.TEST_MIGRATOR_PASSWORD,
  ssl: { ca: readFileSync(process.env.PGSSLROOTCERT, 'utf8'), rejectUnauthorized: true },
  options: '-c role=shipments_owner -c timezone=UTC -c statement_timeout=20000', connectionTimeoutMillis: 10_000 });
async function http(account, path, body, expected = 200) {
  const response = await fetch('http://127.0.0.1:3000' + path, { method: body ? 'POST' : 'GET',
    headers: { Authorization: `Bearer ${tokens[account]}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(35_000) });
  const data = await response.json();
  assert.equal(response.status, expected, JSON.stringify(data));
  return data;
}
async function lag() {
  const before = await http(b, '/reports');
  await http(b, '/shipments/b0000000-0000-4000-8000-000000000002/transitions',
    { requestId: 'paused-dispatch', expectedRevision: 0, toStatus: 'dispatched' }, 201);
  assert.equal((await http(b, '/shipments/b0000000-0000-4000-8000-000000000002')).revision, 1);
  const after = await http(b, '/reports');
  assert.deepEqual(after.rows, before.rows);
  console.log('Confirmed Paused pipeline: PG accepted dispatch/current revision 1 while analytical report retained its older exact groups');
}
async function outage() {
  await admin.command({ query: 'REVOKE SELECT ON default.cdc_shipment_events FROM shipments_reports' });
  try {
    await Promise.all([http(a, '/reports', undefined, 503), http(b, '/reports', undefined, 503)]);
    await http(b, '/shipments/b0000000-0000-4000-8000-000000000003/transitions',
      { requestId: 'analytics-outage-dispatch', expectedRevision: 0, toStatus: 'dispatched' }, 201);
    assert.equal((await http(b, '/shipments/b0000000-0000-4000-8000-000000000003')).revision, 1);
    console.log('Both analytical capacity slots returned bounded 503 during SELECT outage; independent PG transition returned 201 and current revision 1');
  } finally { await admin.command({ query: 'GRANT SELECT ON default.cdc_shipment_events TO shipments_reports' }); }
  await Promise.all([http(a, '/reports'), http(b, '/reports')]);
  console.log('Both report slots recovered to 200 on the same server/client after table SELECT restoration');
}
async function reader() {
  const client = createClient({ url: process.env.CLICKHOUSE_URL, username: process.env.CLICKHOUSE_USER,
    password: process.env.CLICKHOUSE_PASSWORD, request_timeout: 10_000 });
  try {
    for (const query of ['CREATE TABLE default.forbidden(x Int32) ENGINE=Memory',
      'INSERT INTO default.cdc_shipment_events(event_id) VALUES(generateUUIDv4())', 'SELECT name FROM system.users LIMIT 1']) {
      await assert.rejects(client.command({ query }), error => ['164', '497'].includes(error.code));
      console.log('Analytical reader rejected:', query.split(' ').slice(0, 4).join(' '));
    }
  } finally { await client.close(); }
  const wrong = createClient({ url: process.env.CLICKHOUSE_URL, username: process.env.CLICKHOUSE_USER,
    password: process.env.CLICKHOUSE_PASSWORD, tls: { ca_cert: readFileSync(process.env.TEST_WRONG_CA) }, request_timeout: 10_000 });
  try { await assert.rejects(wrong.command({ query: 'SELECT 1' }), error => {
      console.log('Untrusted analytical CA TLS code:', error.code);
      return ['SELF_SIGNED_CERT_IN_CHAIN', 'UNABLE_TO_GET_ISSUER_CERT_LOCALLY', 'UNABLE_TO_VERIFY_LEAF_SIGNATURE'].includes(error.code);
    });
    console.log('Analytical HTTPS connection rejected an independent untrusted CA');
  } finally { await wrong.close(); }
}
async function tombstone() {
  // Controlled privileged maintenance only. Runtime UPDATE/DELETE were proven denied.
  const { rows } = await owner.query("DELETE FROM shipments.events WHERE account_id=$1 AND request_id='cancel-created' RETURNING *, event_day::text AS probe_day", [a]);
  assert.equal(rows.length, 1);
  const event = rows[0];
  try {
    const deadline = Date.now() + 180_000;
    let observed = false;
    // PostgreSQL DATE is a calendar value; avoid a local-midnight Date -> UTC conversion.
    const day = event.probe_day;
    console.log('Delete probe identity:', JSON.stringify({ account: a, day, event: event.event_id, pgDateType: typeof event.event_day }));
    let attempts = 0;
    do {
      const result = await admin.query({ query: `SELECT account_id,event_day,event_id,toUInt8(_peerdb_is_deleted) AS deleted,toString(_peerdb_version) AS version FROM default.cdc_shipment_events FINAL
        WHERE account_id={account:UUID} AND event_day={day:Date32} AND event_id={event:UUID} LIMIT 1`,
        query_params: { account: a, day, event: event.event_id }, format: 'JSONEachRow' });
      try {
        const versions = await result.json();
        if (attempts++ < 3 || versions[0]?.deleted === 1) console.log('FINAL probe:', JSON.stringify(versions));
        observed = versions[0]?.deleted === 1;
      } finally { result.close(); }
      if (observed) break;
      await pause(3000);
    } while (Date.now() < deadline);
    assert.equal(observed, true);
    const report = await http(a, '/reports');
    const expected = await owner.query(`SELECT event_day::text AS "eventDay", service_level AS "serviceLevel", to_status AS "toStatus",
      count(*)::text AS events, count(*) FILTER (WHERE to_status='delivered')::text AS "deliveredCount",
      coalesce(sum(duration_ms) FILTER (WHERE to_status='delivered'),0)::text AS "totalDurationMs",
      coalesce(max(duration_ms) FILTER (WHERE to_status='delivered'),0)::text AS "maxDurationMs"
      FROM shipments.events WHERE account_id=$1 AND event_day BETWEEN (current_timestamp AT TIME ZONE 'UTC')::date-6 AND (current_timestamp AT TIME ZONE 'UTC')::date
      GROUP BY event_day,service_level,to_status ORDER BY event_day,service_level,to_status`, [a]);
    assert.deepEqual(report.rows, expected.rows);
    const count = await admin.query({ query: `SELECT toString(count()) AS n FROM default.cdc_shipment_events FINAL
      WHERE account_id={account:UUID} AND event_id={event:UUID} AND _peerdb_is_deleted=0`,
      query_params: { account: a, event: event.event_id }, format: 'JSONEachRow' });
    try { assert.equal((await count.json())[0].n, '0'); } finally { count.close(); }
    console.log('Privileged fixture DELETE produced a FINAL tombstone; live-row filter excludes it and all deleted-state report aggregates exactly equal current PG');
  } finally {
    const columns = ['event_id','account_id','shipment_id','request_id','expected_revision','revision','from_status','to_status',
      'service_level','event_at','event_day','dispatched_at','duration_ms'];
    await owner.query(`INSERT INTO shipments.events(${columns.join(',')}) VALUES(${columns.map((_, i) => `$${i + 1}`).join(',')})`, columns.map(c => event[c]));
    console.log('Restored exact immutable fixture event/identity through privileged test role; final equality check must observe the newer live version');
  }
}
try {
  const mode = process.argv[2];
  if (mode === 'lag') await lag();
  else if (mode === 'outage') await outage();
  else if (mode === 'reader') await reader();
  else if (mode === 'tombstone') await tombstone();
  else throw new Error('Use lag, outage, reader or tombstone');
} finally { await Promise.all([admin.close(), owner.end()]); }
