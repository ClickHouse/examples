import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import pg from 'pg';
const config = {
  host: process.env.PGHOST, port: Number(process.env.PGPORT), database: process.env.PGDATABASE,
  ssl: { ca: readFileSync(process.env.PGSSLROOTCERT, 'utf8'), rejectUnauthorized: true },
  connectionTimeoutMillis: 10_000, query_timeout: 20_000,
};
const app = new pg.Pool({ ...config, user: 'shipments_app', password: process.env.PGPASSWORD });
const cdc = new pg.Pool({ ...config, user: 'shipments_cdc', password: process.env.TEST_CDC_PASSWORD });
async function rejected(pool, sql, code, values) {
  await assert.rejects(pool.query(sql, values), error => error.code === code);
  console.log(`Rejected ${code}: ${sql.split(' ').slice(0, 4).join(' ')}`);
}
try {
  const tls = (await app.query('SELECT ssl, version FROM pg_stat_ssl WHERE pid=pg_backend_pid()')).rows[0];
  assert.equal(tls.ssl, true);
  console.log('Verified Cloud CA + hostname connection:', tls);
  for (const sql of [
    'UPDATE shipments.events SET duration_ms=0', 'DELETE FROM shipments.events',
    'CREATE TABLE shipments.forbidden(id int)', 'INSERT INTO shipments.shipments(shipment_id) VALUES(NULL)',
  ]) await rejected(app, sql, '42501');
  await rejected(cdc, 'SELECT * FROM shipments.shipments LIMIT 1', '42501');
  const insert = `INSERT INTO shipments.events(event_id,account_id,shipment_id,request_id,expected_revision,revision,
    from_status,to_status,service_level,event_at,event_day,dispatched_at,duration_ms)
    VALUES($1,$2,$3,$4,0,1,'created','dispatched','standard',date_trunc('milliseconds',current_timestamp),
    (current_timestamp AT TIME ZONE 'UTC')::date,
    CASE WHEN $5::timestamptz IS NULL THEN NULL ELSE date_trunc('milliseconds',current_timestamp) END,0)`;
  await rejected(app, insert, '23503', [randomUUID(), '00000000-0000-4000-8000-000000000002',
    'a0000000-0000-4000-8000-000000000006', 'fk-probe', new Date()]);
  await rejected(app, insert, '23514', [randomUUID(), '00000000-0000-4000-8000-000000000001',
    'a0000000-0000-4000-8000-000000000006', 'null-dispatch-probe', null]);
  // This independent untrusted CA is generated for this test, not a TLS opt-out.
  const wrong = new pg.Pool({ ...config, user: 'shipments_app', password: process.env.PGPASSWORD,
    ssl: { ca: readFileSync(process.env.TEST_WRONG_CA, 'utf8'), rejectUnauthorized: true } });
  try {
    await assert.rejects(wrong.query('SELECT 1'), error => {
      console.log('Untrusted PG CA TLS code:', error.code);
      return ['SELF_SIGNED_CERT_IN_CHAIN', 'UNABLE_TO_GET_ISSUER_CERT_LOCALLY', 'UNABLE_TO_VERIFY_LEAF_SIGNATURE'].includes(error.code);
    });
    console.log('Untrusted CA connection rejected before SQL execution');
  } finally { await wrong.end(); }
} finally { await Promise.all([app.end(), cdc.end()]); }
