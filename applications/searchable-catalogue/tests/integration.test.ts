import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { checkServerIdentity } from 'node:tls';
import pg from 'pg';
import { sql } from 'kysely';
import { buildApp } from '../src/app.js';
import { database, poolOptions } from '../src/database.js';

const secret = process.env.CURSOR_SECRET ?? '';
const writer = database('catalogue_migrator', process.env.TEST_MIGRATOR_PASSWORD);
let app = await buildApp(database(), secret);
let base = await app.listen({ host: '127.0.0.1', port: 0 });
async function get(path: string) { const response = await fetch(base + path); return { status: response.status, body: await response.json() as any }; }
const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
async function pages(path: string, limit: number) {
  const items: any[] = []; let cursor: string | null = null;
  do {
    const result = await get(`/products?${path}&limit=${limit}${cursor ? `&cursor=${cursor}` : ''}`);
    assert.equal(result.status, 200); items.push(...result.body.items); cursor = result.body.next_cursor;
  } while (cursor);
  return items;
}
await test('real Cloud catalogue workflow over HTTP', async t => {
  try {
    await t.test('all tied prices traverse once at page sizes 1, 2 and 4', async () => {
      const baseline = await pages('', 100);
      assert.equal(baseline.length, 11);
      for (const limit of [1,2,4]) assert.deepEqual(await pages('', limit), baseline);
      assert.equal(new Set(baseline.map(p => p.id)).size, 11);
    });
    await t.test('full-text search, category and inclusive price filters', async () => {
      const items = await pages('q=camping&category=camping&min_price=1800&max_price=4500', 1);
      assert.deepEqual(items.map(p => p.id), [id(1),id(2),id(3)]);
      assert.equal((await pages('q=definitelyabsentword', 2)).length, 0);
      assert.equal((await pages("q=%27%20OR%201%3D1%20--", 2)).length, 0);
    });
    await t.test('cursor tampering and changed filters are rejected', async () => {
      const first = await get('/products?category=camping&limit=1');
      const cursor = first.body.next_cursor as string;
      assert.equal((await get(`/products?category=cycling&cursor=${cursor}`)).status, 400);
      assert.equal((await get(`/products?category=camping&cursor=x${cursor}`)).status, 400);
      assert.equal((await get('/products?cursor=abc')).status, 400);
      assert.equal((await get(`/products?category=camping&limit=2&cursor=${cursor}`)).status, 200);
    });
    await t.test('invalid bounds, unknown parameters, oversized text and invalid IDs', async () => {
      for (const query of ['limit=0','limit=101','limit=1.5','min_price=-1','min_price=9&max_price=2','category=toys','extra=1','q='+ 'x'.repeat(121)])
        assert.equal((await get('/products?' + query)).status, 400, query);
      assert.equal((await get('/products/not-a-uuid')).status, 400);
      assert.equal((await get('/products/' + id(12))).status, 404);
      assert.equal((await get('/products/' + id(1))).status, 200);
      assert.equal((await fetch(base + '/products', { method: 'POST' })).status, 404);
    });
    await t.test('new cheaper insertion does not shift continuation; later insertion is visible', async () => {
      const first = await get('/products?limit=2');
      await writer.insertInto('products').values([
        { id:id(101),sku:'TEST-101',name:'Earlier fixture',description:'fixture',category:'camping',price_pence:100,active:true },
        { id:id(102),sku:'TEST-102',name:'Later fixture',description:'fixture',category:'camping',price_pence:2000,active:true },
      ]).execute();
      const continuation = await get('/products?limit=100&cursor=' + first.body.next_cursor);
      assert(!continuation.body.items.some((p: any) => p.id === id(101)));
      assert(continuation.body.items.some((p: any) => p.id === id(102)));
      assert(!continuation.body.items.some((p: any) => first.body.items.some((f: any) => f.id === p.id)));
      await writer.deleteFrom('products').where('id', 'in', [id(101),id(102)]).execute();
    });
    await t.test('price changes can repeat earlier products or omit moved unseen products', async () => {
      const first = await get('/products?limit=2');
      await writer.updateTable('products').set({price_pence:6000}).where('id','=',id(1)).execute();
      await writer.updateTable('products').set({price_pence:100}).where('id','=',id(3)).execute();
      const next = await get('/products?limit=100&cursor='+first.body.next_cursor);
      assert(next.body.items.some((p: any) => p.id === id(1)));
      assert(!next.body.items.some((p: any) => p.id === id(3)));
      await writer.updateTable('products').set({price_pence:1800}).where('id','=',id(1)).execute();
      await writer.updateTable('products').set({price_pence:4500}).where('id','=',id(3)).execute();
    });
    await t.test('runtime role cannot write or change schema even after read-only is disabled', async () => {
      const db = database();
      try {
        await assert.rejects(sql`INSERT INTO catalogue.products (id) VALUES (${id(103)}::uuid)`.execute(db));
        await assert.rejects(db.transaction().execute(async tx => {
          await sql`SET TRANSACTION READ WRITE`.execute(tx);
          await sql`UPDATE catalogue.products SET price_pence = 0`.execute(tx);
        }), (error: any) => error.code === '42501');
        await assert.rejects(db.transaction().execute(async tx => {
          await sql`SET TRANSACTION READ WRITE`.execute(tx);
          await sql`CREATE TABLE catalogue.denied (id INTEGER)`.execute(tx);
        }), (error: any) => error.code === '42501');
      } finally { await db.destroy(); }
    });
    await t.test('TLS validates CA and hostname', async () => {
      const wrongCa = process.env.TEST_WRONG_CA;
      assert(wrongCa, 'TEST_WRONG_CA is required');
      for (const kind of ['ca', 'host']) {
        const options = poolOptions();
        const ssl = options.ssl as import('node:tls').ConnectionOptions;
        if (kind === 'ca') ssl.ca = readFileSync(wrongCa, 'utf8');
        else ssl.checkServerIdentity = (_name, cert) => checkServerIdentity('wrong.invalid', cert);
        const client = new pg.Client(options);
        try { await assert.rejects(client.connect(), (error: any) => kind === 'host'
          ? error.code === 'ERR_TLS_CERT_ALTNAME_INVALID' : /CERT|VERIFY|SELF_SIGNED/.test(error.code)); }
        finally { await client.end(); }
      }
    });
    await t.test('API restart preserves data and signed cursor continuation', async () => {
      const first = await get('/products?limit=2');
      await app.close(); app = await buildApp(database(), secret);
      base = await app.listen({host:'127.0.0.1',port:0});
      assert.equal((await get('/products/'+id(1))).body.name,'Trail flask');
      assert.equal((await get('/products?cursor='+first.body.next_cursor)).body.items.length,9);
    });
  } finally {
    await writer.deleteFrom('products').where('id','in',[id(101),id(102)]).execute();
    await writer.updateTable('products').set({price_pence:1800}).where('id','=',id(1)).execute();
    await writer.updateTable('products').set({price_pence:4500}).where('id','=',id(3)).execute();
    await app.close(); await writer.destroy();
  }
});
