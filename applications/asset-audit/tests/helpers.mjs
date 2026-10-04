import { createRequire } from 'node:module'
import { readFileSync } from 'node:fs'
import { spawn } from 'node:child_process'
const require = createRequire(new URL('../api/package.json', import.meta.url))
const { Client } = require('pg')
export const base = process.env.APP_ORIGIN ?? 'http://127.0.0.1:3333'
export async function client(owner = false) {
  if (owner && !process.env.TEST_OWNER_PASSWORD) throw new Error('TEST_OWNER_PASSWORD is required; use a dedicated fixture')
  const c = new Client({
    host: process.env.DB_HOST, port: Number(process.env.DB_PORT), database: process.env.DB_DATABASE,
    user: owner ? 'asset_audit_owner' : process.env.DB_USER,
    password: owner ? process.env.TEST_OWNER_PASSWORD : process.env.DB_PASSWORD,
    ssl: { ca: readFileSync(process.env.PG_CA_CERT_PATH, 'utf8'), rejectUnauthorized: true, servername: process.env.DB_HOST },
  })
  await c.connect()
  return c
}
export async function fixture(owner, name = 'Browser equipment stocktake') {
  const id = 100000 + Math.floor(Math.random() * 100000000)
  await owner.query('INSERT INTO asset_audit.stocktakes (id, name, location) VALUES ($1, $2, $3)', [id, name, 'North workshop'])
  await owner.query('INSERT INTO asset_audit.count_rows (stocktake_id,item_id,expected_quantity) SELECT $1,id,quantity FROM asset_audit.items', [id])
  return id
}
export async function removeFixture(owner, id) {
  await owner.query('DELETE FROM asset_audit.count_rows WHERE stocktake_id=$1', [id])
  await owner.query('DELETE FROM asset_audit.stocktakes WHERE id=$1', [id])
}
export async function request(path, method = 'GET', body) {
  const response = await fetch(base + path, {
    method, headers: { Origin: base, 'X-Asset-Audit': '1', 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  })
  return { status: response.status, body: await response.json() }
}
export async function startServer() {
  const child = spawn(process.execPath, ['bin/server.js'], { cwd: new URL('../api/build/', import.meta.url), env: process.env, stdio: ['ignore', 'ignore', 'pipe'] })
  let stderr = ''
  child.stderr.on('data', (chunk) => { stderr += chunk })
  for (let i = 0; i < 100; i++) {
    if (child.exitCode !== null) throw new Error('API exited before readiness: ' + stderr.slice(-1000))
    try { const r = await request('/api/stocktakes'); if (r.status === 200) return child } catch {}
    await new Promise((resolve) => setTimeout(resolve, 100))
  }
  child.kill('SIGTERM')
  throw new Error('API did not become ready')
}
export async function stopServer(child) {
  if (child.exitCode !== null) return
  const closed = new Promise((resolve) => child.once('exit', resolve))
  child.kill('SIGTERM')
  await closed
}
