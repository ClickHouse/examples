import assert from 'node:assert/strict'
import { request as httpRequest } from 'node:http'
import { client, fixture, removeFixture, request, startServer, stopServer, base } from './helpers.mjs'
const owner = await client(true)
const runtime = await client()
let server
let id
try {
  id = await fixture(owner, 'HTTP transaction test')
  server = await startServer()
  let result = await request('/api/stocktakes/' + id)
  assert.equal(result.status, 200)
  const initial = result.body
  const counts = initial.rows.map((r) => ({ itemId: r.itemId, counted: r.expected }))
  const save = (revision, rows = counts) => request('/api/stocktakes/' + id, 'PUT', { revision, counts: rows })
  const finalize = (revision) => request('/api/stocktakes/' + id + '/finalize', 'POST', { revision })

  assert.equal((await finalize(0)).status, 422)
  assert.equal((await save(0, counts.map((r, i) => ({ ...r, counted: i === 0 ? -1 : r.counted })))).status, 422)
  assert.equal((await save(0, counts.map((r, i) => ({ ...r, counted: i === 0 ? 1.5 : r.counted })))).status, 422)
  assert.equal((await save(0, counts.slice(1))).status, 422)
  assert.equal((await save(0, counts.map((r, i) => i === 1 ? counts[0] : r))).status, 422)
  const badOrigin = await fetch(base + '/api/stocktakes/' + id, { method: 'PUT', headers: { Origin: 'https://wrong.example', 'X-Asset-Audit': '1', 'Content-Type': 'application/json' }, body: JSON.stringify({ revision: 0, counts }) })
  assert.equal(badOrigin.status, 403)
  const badHostStatus = await new Promise((resolve, reject) => {
    const req = httpRequest(base + '/api/stocktakes', { headers: { Host: 'wrong.example' } }, (res) => { res.resume(); resolve(res.statusCode) })
    req.on('error', reject)
    req.end()
  })
  assert.equal(badHostStatus, 403)

  const attempts = await Promise.all([save(0), save(0)])
  assert.deepEqual(attempts.map((r) => r.status).sort(), [200, 409])
  result = await request('/api/stocktakes/' + id)
  assert.equal(result.body.revision, 1)
  assert.deepEqual(result.body.rows.map((r) => r.counted), counts.map((r) => r.counted))
  await stopServer(server)
  server = await startServer()
  result = await request('/api/stocktakes/' + id)
  assert.equal(result.body.revision, 1)
  assert.deepEqual(result.body.rows.map((r) => r.counted), counts.map((r) => r.counted))
  console.log('PASS persisted draft after genuine API process restart; input, origin, row membership and competing saves')

  // Force the last row update to fail after earlier rows were changed.
  const last = counts.at(-1)
  await owner.query(`ALTER TABLE asset_audit.count_rows ADD CONSTRAINT test_asset_failure CHECK (stocktake_id <> ${id} OR item_id <> ${last.itemId} OR counted_quantity <> 887)`)
  const failedCounts = counts.map((r) => ({ ...r, counted: r.itemId === last.itemId ? 887 : r.counted + 1 }))
  assert.equal((await save(1, failedCounts)).status, 500)
  result = await request('/api/stocktakes/' + id)
  assert.equal(result.body.revision, 1)
  assert.deepEqual(result.body.rows.map((r) => r.counted), counts.map((r) => r.counted))
  await owner.query('ALTER TABLE asset_audit.count_rows DROP CONSTRAINT test_asset_failure')
  console.log('PASS late-row database failure rolls back every count and header revision')

  const race = await Promise.all([save(1), finalize(1)])
  assert.deepEqual(race.map((r) => r.status).sort(), [200, 409])
  result = await request('/api/stocktakes/' + id)
  if (result.body.status === 'draft') assert.equal((await finalize(result.body.revision)).status, 200)
  result = await request('/api/stocktakes/' + id)
  assert.equal(result.body.status, 'finalized')
  assert.equal((await save(result.body.revision)).status, 409)
  assert.equal((await finalize(result.body.revision)).status, 409)
  await assert.rejects(runtime.query('UPDATE asset_audit.count_rows SET counted_quantity=1 WHERE stocktake_id=$1', [id]), /immutable/)
  await assert.rejects(runtime.query('UPDATE asset_audit.stocktakes SET revision=revision+1 WHERE id=$1', [id]), /immutable/)
  await assert.rejects(runtime.query("UPDATE asset_audit.items SET quantity=0"), /permission denied/)
  await assert.rejects(runtime.query('CREATE TABLE asset_audit.runtime_should_not_create (id integer)'), /permission denied/)
  await assert.rejects(runtime.query('DELETE FROM asset_audit.count_rows WHERE stocktake_id=$1', [id]), /permission denied/)
  console.log('PASS save/finalize race; immutable finalized sheets; restricted runtime grants')
} finally {
  if (server) await stopServer(server)
  await owner.query('ALTER TABLE asset_audit.count_rows DROP CONSTRAINT IF EXISTS test_asset_failure')
  if (id) await removeFixture(owner, id)
  await runtime.end()
  await owner.end()
}
