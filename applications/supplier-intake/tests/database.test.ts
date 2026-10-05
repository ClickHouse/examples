import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { lookup } from 'node:dns/promises';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { Pool } from 'pg';
import { database, databaseConfig, closeDatabase } from '../src/lib/server/database';
import {
  stageUpload,
  reviewBatch,
  promoteBatch,
  getBatch,
  RevisionConflict,
} from '../src/lib/server/intake';
import { IntakeError } from '../src/lib/server/parsers';
import type { Mapping } from '../src/lib/mapping';
const mapping = (id: string, supplier: string): Mapping => ({
  batchId: id,
  revision: 1,
  supplier,
  sku: 'Code',
  product: 'Name',
  price: 'USD',
  stock: 'Qty',
});
test('managed intake: duplicate requests, competing reviews, atomic rollback, grants and verified TLS', async (t) => {
  try {
    const identity = (await database().query('SELECT current_user,version() AS version'))
      .rows[0];
    assert.equal(identity.current_user, 'intake_app');
    console.log(JSON.stringify(identity));
    const key = randomUUID().slice(0, 8).toUpperCase();
    const csv = Buffer.from(
      `Code,Name,USD,Qty\nA_${key},Tea towel,8.00,4\nB_${key},Market tote,12.50,9\n`,
    );
    const staged = await Promise.all([
      stageUpload(csv, 'concurrent.csv'),
      stageUpload(csv, 'concurrent.csv'),
    ]);
    assert.equal(staged[0].id, staged[1].id);
    assert.equal(staged.filter((value) => !value.reused).length, 1);
    const id = staged[0].id;
    const supplier = `Integration ${key}`;
    assert.equal((await getBatch(id)).rows.length, 2);
    await assert.rejects(
      reviewBatch({ ...mapping(id, supplier), price: 'Unknown' }),
      IntakeError,
    );
    const reviews = await Promise.allSettled([
      reviewBatch(mapping(id, supplier)),
      reviewBatch(mapping(id, supplier)),
    ]);
    assert.equal(reviews.filter((value) => value.status === 'fulfilled').length, 1);
    const rejected = reviews.find(
      (value) => value.status === 'rejected',
    ) as PromiseRejectedResult;
    assert.ok(rejected.reason instanceof RevisionConflict);
    const promotions = await Promise.all([promoteBatch(id, 2), promoteBatch(id, 2)]);
    assert.equal(promotions.filter((value) => !value.reused).length, 1);
    assert.equal(
      (
        await database().query(
          'SELECT count(*)::integer AS count FROM intake.products WHERE batch_id=$1',
          [id],
        )
      ).rows[0].count,
      2,
    );
    assert.equal((await promoteBatch(id, 2)).reused, true);

    const snapshot = await stageUpload(
      Buffer.from(`Code,Name,USD,Qty,Alternate\nSNAP_${key},Snapshot row,8.00,4,9.00\n`),
      'snapshot.csv',
    );
    await reviewBatch(mapping(snapshot.id, supplier));
    // Pause the real reader after its header query. The actual review service
    // commits another mapping before that reader queries staging rows, forcing
    // the interleaving that a pair of read-committed queries would mishandle.
    let headerRead!: () => void;
    let continueRead!: () => void;
    const ready = new Promise<void>((resolve) => {
      headerRead = resolve;
    });
    const release = new Promise<void>((resolve) => {
      continueRead = resolve;
    });
    const pool = database();
    const originalConnect = pool.connect.bind(pool);
    let intercepted = false;
    const mock = t.mock.method(pool, 'connect', async () => {
      const client = await originalConnect();
      if (intercepted) return client;
      intercepted = true;
      return new Proxy(client, {
        get(target, property) {
          if (property === 'query')
            return async (sql: string, ...params: any[]) => {
              const result = await (
                target.query.bind(target) as (...values: any[]) => Promise<any>
              )(sql, ...params);
              if (sql.includes('to_char') && sql.includes('WHERE id=$1')) {
                headerRead();
                await release;
              }
              return result;
            };
          const value = Reflect.get(target, property);
          return typeof value === 'function' ? value.bind(target) : value;
        },
      });
    });
    try {
      const reading = getBatch(snapshot.id);
      await ready;
      await reviewBatch({
        ...mapping(snapshot.id, supplier),
        revision: 2,
        price: 'Alternate',
      });
      continueRead();
      const coherent = await reading;
      assert.equal(coherent.batch.revision, 2);
      assert.equal(coherent.batch.mapping!.price, 'USD');
      assert.equal(coherent.rows[0].mapped!.cents, 800);
    } finally {
      continueRead();
      mock.mock.restore();
    }
    const current = await getBatch(snapshot.id);
    assert.equal(current.batch.revision, 3);
    assert.equal(current.rows[0].mapped!.cents, 900);

    const invalid = await stageUpload(
      Buffer.from(
        `Code,Name,USD,Qty\nOK_${key},Valid row,5.00,3\nBAD_${key},Invalid row,ask,-2\n`,
      ),
      'invalid.csv',
    );
    assert.equal((await reviewBatch(mapping(invalid.id, supplier))).invalidCount, 1);
    await assert.rejects(promoteBatch(invalid.id, 2), IntakeError);
    assert.equal(
      (
        await database().query(
          'SELECT count(*)::integer AS count FROM intake.products WHERE batch_id=$1',
          [invalid.id],
        )
      ).rows[0].count,
      0,
    );

    const conflicting = await stageUpload(
      Buffer.from(
        `Code,Name,USD,Qty\nROLL_${key},Otherwise valid,1.00,1\nBASE001,Existing SKU,25.00,20\n`,
      ),
      'rollback.csv',
    );
    await reviewBatch(mapping(conflicting.id, 'Willow Cooperative'));
    await assert.rejects(promoteBatch(conflicting.id, 2), /No rows were imported/);
    assert.equal(
      (
        await database().query(
          'SELECT count(*)::integer AS count FROM intake.products WHERE batch_id=$1',
          [conflicting.id],
        )
      ).rows[0].count,
      0,
    );
    assert.equal((await getBatch(conflicting.id)).batch.status, 'reviewed');
    assert.equal(
      (
        await database().query(
          "SELECT price_cents FROM intake.products WHERE supplier_key='willow cooperative' AND sku='BASE001'",
        )
      ).rows[0].price_cents,
      1250,
    );
    for (const sql of [
      'CREATE TABLE intake.forbidden (id integer)',
      'ALTER TABLE intake.products ADD COLUMN forbidden text',
      'UPDATE intake.products SET stock=0',
      'DELETE FROM intake.products',
    ])
      await assert.rejects(database().query(sql), (err: any) => err.code === '42501');

    const config = databaseConfig();
    const ip = new URL(process.env.DATABASE_URL!);
    ip.hostname = (await lookup(ip.hostname, { family: 4 })).address;
    const wrongName = new Pool({
      ...config,
      connectionString: ip.toString(),
      max: 1,
      ssl: { ...(config.ssl as object), servername: 'wrong-host.invalid' },
    });
    try {
      await assert.rejects(
        wrongName.query('SELECT 1'),
        (err: any) => err.code === 'ERR_TLS_CERT_ALTNAME_INVALID',
      );
    } finally {
      await wrongName.end();
    }
    const directory = mkdtempSync(join(tmpdir(), 'intake-ca-'));
    try {
      execFileSync(
        'openssl',
        [
          'req',
          '-x509',
          '-newkey',
          'rsa:2048',
          '-nodes',
          '-keyout',
          join(directory, 'key.pem'),
          '-out',
          join(directory, 'ca.pem'),
          '-days',
          '1',
          '-subj',
          '/CN=unrelated-intake-root',
        ],
        { stdio: 'ignore' },
      );
      const wrongCa = new Pool({
        ...config,
        max: 1,
        ssl: {
          ...(config.ssl as object),
          ca: readFileSync(join(directory, 'ca.pem'), 'utf8'),
        },
      });
      try {
        await assert.rejects(wrongCa.query('SELECT 1'), (err: any) =>
          [
            'UNABLE_TO_VERIFY_LEAF_SIGNATURE',
            'UNABLE_TO_GET_ISSUER_CERT_LOCALLY',
            'SELF_SIGNED_CERT_IN_CHAIN',
            'DEPTH_ZERO_SELF_SIGNED_CERT',
          ].includes(err.code),
        );
      } finally {
        await wrongCa.end();
      }
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
    console.log(
      'Verified upload replay, competing review, concurrent read/review snapshot, concurrent promotion replay, invalid-batch rejection, supplier-SKU rollback, runtime grants, wrong CA and hostname.',
    );
  } finally {
    await closeDatabase();
  }
});
