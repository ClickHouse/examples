import assert from 'node:assert/strict';
import { spawn, execFileSync } from 'node:child_process';
import { once } from 'node:events';
import { createWriteStream, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import http from 'node:http';
import { randomBytes } from 'node:crypto';
import { chromium } from 'playwright';

const origin = process.env.APP_ORIGIN || 'http://127.0.0.1:5000';
const evidence = process.env.EVIDENCE_DIR;
assert(evidence, 'EVIDENCE_DIR must point outside the repository');
mkdirSync(evidence, { recursive: true });
const connectionFields = ['PGHOST', 'PGPORT', 'PGDATABASE', 'PGSSLROOTCERT'];
const owner = { PATH: process.env.PATH, PGSSLMODE: 'verify-full',
  PGUSER: 'capacity_migration', PGPASSWORD: process.env.MIGRATION_PASSWORD };
const observer = { ...owner, PGUSER: process.env.ADMIN_USER, PGPASSWORD: process.env.ADMIN_PASSWORD };
for (const field of connectionFields) { owner[field] = process.env[field]; observer[field] = process.env[field]; }
const runtime = { PATH: process.env.PATH, DOTNET_ROOT: process.env.DOTNET_ROOT,
  APP_ORIGIN: origin, ASPNETCORE_ENVIRONMENT: 'Production', PGUSER: 'capacity_app', PGPASSWORD: process.env.PGPASSWORD };
for (const field of connectionFields) runtime[field] = process.env[field];
const sql = (query, env = owner) => execFileSync('psql', ['-X', '-v', 'ON_ERROR_STOP=1', '-tAc', query],
  { env, encoding: 'utf8', timeout: 10000 }).trim();
async function sqlSession(env) {
  const client = spawn('psql', ['-X', '-qAt', '-P', 'pager=off', '-v', 'ON_ERROR_STOP=1'], { env });
  let pending;
  let buffer = '';
  client.stdout.on('data', chunk => {
    buffer += chunk;
    let newline;
    while ((newline = buffer.indexOf('\n')) >= 0) {
      const line = buffer.slice(0, newline); buffer = buffer.slice(newline + 1);
      if (!pending) continue;
      if (line === pending.marker) { clearTimeout(pending.timer); pending.resolve(pending.rows.join('\n')); pending = null; }
      else pending.rows.push(line);
    }
  });
  client.on('exit', () => { if (pending) pending.reject(new Error('SQL control session exited')); });
  const query = statement => new Promise((resolve, reject) => {
    assert(!pending, 'SQL controls are sequential');
    const marker = randomBytes(8).toString('hex');
    const timer = setTimeout(() => reject(new Error('SQL control timeout')), 5000);
    pending = { marker, timer, resolve, reject, rows: [] };
    client.stdin.write(statement + `;\nSELECT '${marker}';\n`);
  });
  await query('SELECT 1');
  return { query, close: async () => { const exited = once(client, 'exit'); client.stdin.end(); await exited; } };
}
const snapshotQuery = `SELECT json_build_object('revision',b.revision,'items',
  (SELECT json_agg(json_build_object('id',id,'name',name,'points',points) ORDER BY position)
   FROM capacity_board.work_items WHERE board_id=b.id))::text FROM capacity_board.boards b`;
const snapshot = () => sql(`SELECT json_build_object('revision',b.revision,'items',
  (SELECT json_agg(json_build_object('id',id,'name',name,'points',points) ORDER BY position)
   FROM capacity_board.work_items WHERE board_id=b.id))::text FROM capacity_board.boards b`);
let child;
async function start() {
  child = spawn(process.env.CAPACITY_EXECUTABLE, [], { env: runtime });
  const log = createWriteStream(join(evidence, `server-${child.pid}.log`));
  child.stdout.pipe(log); child.stderr.pipe(log);
  for (let attempt = 0; attempt < 100; attempt++) {
    if (child.exitCode !== null) throw new Error('server exited before readiness');
    try { if ((await fetch(`${origin}/health`)).status === 200) return child.pid; } catch {}
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error('server did not become ready');
}
async function stop() {
  const ending = child;
  const exited = once(ending, 'exit');
  ending.kill('SIGTERM');
  const [code] = await Promise.race([exited, new Promise((_, reject) =>
    setTimeout(() => reject(new Error('server shutdown timeout')), 15000).unref())]);
  assert.equal(code, 0, 'original process must exit successfully before replacement');
  assert.notEqual(ending.exitCode, null);
  return ending.pid;
}
async function socketStatus(token, sentOrigin) {
  return new Promise((resolve, reject) => {
    const request = http.request(`${origin}/_blazor?id=${encodeURIComponent(token)}`, {
      headers: { Upgrade: 'websocket', Connection: 'Upgrade', 'Sec-WebSocket-Version': '13',
        'Sec-WebSocket-Key': randomBytes(16).toString('base64'), ...(sentOrigin ? { Origin: sentOrigin } : {}) }
    });
    request.on('response', response => { response.resume(); resolve(response.statusCode); });
    request.on('upgrade', (_, socket) => { socket.destroy(); resolve(101); });
    request.on('error', reject); request.setTimeout(3000, () => request.destroy(new Error('handshake timeout')));
    request.end();
  });
}
const expectMessage = async (page, text) => page.getByRole('status').filter({ hasText: text }).waitFor();
const load = async page => {
  await page.goto(origin);
  await expectMessage(page, 'Committed allocation loaded');
};
const waitRevision = async (page, value) => {
  await page.waitForFunction(value => document.querySelector('#loaded-revision')?.textContent === String(value), value);
};
const save = page => page.getByRole('button', { name: 'Save allocation', exact: true }).click();
let browser;
let holder;
let control;
try {
  const firstPid = await start();
  assert.equal((await fetch(`${origin}/_blazor/negotiate?negotiateVersion=1`, { method: 'POST' })).status, 403);
  assert.equal((await fetch(`${origin}/_blazor/negotiate?negotiateVersion=1`, {
    method: 'POST', headers: { Origin: 'https://evil.example' } })).status, 403);
  const negotiated = await fetch(`${origin}/_blazor/negotiate?negotiateVersion=1`, {
    method: 'POST', headers: { Origin: origin } });
  assert.equal(negotiated.status, 200);
  const negotiation = await negotiated.json();
  assert.deepEqual(negotiation.availableTransports.map(value => value.transport), ['WebSockets', 'LongPolling']);
  assert.equal(await socketStatus(negotiation.connectionToken, 'https://evil.example'), 403);
  assert.equal(await socketStatus(negotiation.connectionToken), 403);
  // Static component form posts retain the framework antiforgery path.
  const unprotectedForm = await fetch(origin, { method: 'POST', headers: { Origin: origin,
    'Content-Type': 'application/x-www-form-urlencoded' }, body: '_handler=allocation' });
  assert.equal(unprotectedForm.status, 400);
  console.log('PASS real negotiation/WebSocket Origin rejection, configured transports and native antiforgery rejection');

  browser = await chromium.launch({ headless: true });
  const errors = [];
  const contextA = await browser.newContext({ viewport: { width: 1280, height: 1000 } });
  const contextB = await browser.newContext({ viewport: { width: 1280, height: 1000 } });
  const a = await contextA.newPage(); const b = await contextB.newPage();
  for (const page of [a, b]) page.on('pageerror', error => errors.push(error.message));
  await load(a); await load(b);
  assert.equal(await a.locator('#committed-total').textContent(), '9');
  await a.getByLabel('Item 1 points', { exact: true }).fill('8');
  await b.getByLabel('Item 1 name', { exact: true }).fill('Second circuit draft');
  await b.getByLabel('Item 1 points', { exact: true }).fill('7');
  await save(a); await expectMessage(a, 'Saved revision 2');
  await save(b); await expectMessage(b, 'Newer committed state exists');
  assert.equal(await b.getByLabel('Item 1 name', { exact: true }).inputValue(), 'Second circuit draft');
  assert.equal(await b.getByLabel('Item 1 points', { exact: true }).inputValue(), '7');
  await waitRevision(b, 1);
  assert.equal(JSON.parse(snapshot()).revision, 2);
  console.log('PASS two actual circuits, stale rejection and preserved draft/displayed revision');

  await b.getByRole('button', { name: 'Reload committed state' }).click(); await waitRevision(b, 2);
  await b.getByLabel('Item 1 points', { exact: true }).fill('30');
  await b.getByLabel('Item 2 points', { exact: true }).fill('30');
  const beforeCapacity = snapshot();
  await save(b); await expectMessage(b, 'draft exceeds capacity');
  assert.equal(snapshot(), beforeCapacity);
  assert.equal(await b.getByLabel('Item 1 points', { exact: true }).inputValue(), '30');
  await b.getByLabel('Item 1 points', { exact: true }).fill('-1');
  await save(b); await expectMessage(b, 'whole number from 0 to 30');
  assert.equal(snapshot(), beforeCapacity);
  await b.getByRole('button', { name: 'Reload committed state' }).click();
  await expectMessage(b, 'Committed allocation loaded');
  await b.getByLabel('Item 1 name', { exact: true }).fill('Bad\u0000name');
  await save(b); await expectMessage(b, 'names of 1–80');
  assert.equal(snapshot(), beforeCapacity);
  console.log('PASS real overcapacity/invalid-integer/NUL rejection without losing the draft or committing changes');

  sql(`CREATE FUNCTION capacity_board.hold_commit() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN IF NEW.response::text LIKE '%Commit held demo%' THEN PERFORM pg_advisory_xact_lock(7521002); END IF;
    RETURN NEW; END $$;
    CREATE CONSTRAINT TRIGGER test_hold AFTER INSERT ON capacity_board.saves DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION capacity_board.hold_commit();`);
  control = await sqlSession(observer);
  holder = spawn('psql', ['-X', '-qAt', '-v', 'ON_ERROR_STOP=1'], { env: owner });
  holder.stdin.write("SET application_name='capacity-board-held-ui'; SELECT pg_advisory_lock(7521002);\n");
  let heldReady = false;
  for (let attempt = 0; attempt < 50; attempt++) {
    const granted = await control.query("SELECT count(*) FROM pg_locks l JOIN pg_stat_activity a ON a.pid=l.pid WHERE l.locktype='advisory' AND l.granted AND a.application_name='capacity-board-held-ui'");
    if (granted === '1') { heldReady = true; break; }
    assert.equal(holder.exitCode, null, 'holder must remain alive');
    await new Promise(resolve => setTimeout(resolve, 10));
  }
  assert(heldReady, 'independent observer must see the actual granted advisory lock');
  await a.getByLabel('Item 1 name', { exact: true }).fill('Commit held demo');
  const beforeHeld = snapshot();
  await save(a);
  await a.getByRole('button', { name: 'Saving…' }).waitFor();
  let observed = false;
  for (let attempt = 0; attempt < 40; attempt++) {
    const count = await control.query("SELECT pg_stat_clear_snapshot(); SELECT count(*) FROM pg_stat_activity WHERE application_name='capacity-board' AND cardinality(pg_blocking_pids(pid))>0");
    if (count.trim() === '1') { observed = true; break; }
    await new Promise(resolve => setTimeout(resolve, 10));
  }
  assert(observed, 'actual COMMIT blocked in deferred trigger');
  assert.equal((await control.query(snapshotQuery)).trim(), beforeHeld);
  await waitRevision(a, 2);
  assert(await a.getByRole('button', { name: 'Saving…' }).isDisabled());
  const released = once(holder, 'exit');
  holder.stdin.end('SELECT pg_advisory_unlock(7521002);\n');
  await released; holder = null;
  await expectMessage(a, 'Saved revision 3');
  await control.close(); control = null;
  sql('DROP TRIGGER test_hold ON capacity_board.saves; DROP FUNCTION capacity_board.hold_commit()');
  console.log('PASS actual deferred COMMIT hold: UI stays pending and shows saved state only after release');

  sql(`CREATE FUNCTION capacity_board.reject_ui_commit() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN IF NEW.response::text LIKE '%Uncertain demo%' THEN RAISE EXCEPTION 'test-only UI commit failure' USING ERRCODE='23514'; END IF;
    RETURN NEW; END $$;
    CREATE CONSTRAINT TRIGGER test_reject AFTER INSERT ON capacity_board.saves DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION capacity_board.reject_ui_commit();`);
  await a.getByLabel('Item 1 name', { exact: true }).fill('Uncertain demo');
  await a.getByLabel('Item 1 points', { exact: true }).fill('9');
  const beforeFailure = snapshot(); const beforeAudits = Number(sql('SELECT count(*) FROM capacity_board.saves'));
  await save(a); await expectMessage(a, "save couldn't be confirmed");
  assert.equal(snapshot(), beforeFailure);
  assert.equal(Number(sql('SELECT count(*) FROM capacity_board.saves')), beforeAudits);
  assert(await a.getByLabel('Item 1 name', { exact: true }).isDisabled());
  assert.equal(await a.getByLabel('Item 1 name', { exact: true }).inputValue(), 'Uncertain demo');
  sql('DROP TRIGGER test_reject ON capacity_board.saves; DROP FUNCTION capacity_board.reject_ui_commit()');
  await a.getByRole('button', { name: 'Retry original save' }).click(); await expectMessage(a, 'Saved revision 4');
  assert.equal(Number(sql('SELECT count(*) FROM capacity_board.saves')), beforeAudits + 1);
  console.log('PASS actual COMMIT error gives uncertain-save UI, paused exact payload and successful original retry');

  await a.getByLabel('Item 1 name', { exact: true }).fill('Unsaved browser value');
  const durable = snapshot();
  assert.equal(await stop(), firstPid);
  const secondPid = await start(); assert.notEqual(secondPid, firstPid);
  const contextC = await browser.newContext({ viewport: { width: 1280, height: 1000 } });
  const c = await contextC.newPage(); c.on('pageerror', error => errors.push(error.message));
  await load(c); await waitRevision(c, 4);
  assert.equal(snapshot(), durable);
  assert.equal(await c.getByLabel('Item 1 name', { exact: true }).inputValue(), 'Uncertain demo');
  console.log(`PASS original process ${firstPid} exited 0 before replacement ${secondPid}; new circuit reloads committed state`);

  await c.getByLabel('Item 1 name', { exact: true }).fill('Café demo ✨');
  await c.getByLabel('Item 1 points', { exact: true }).fill('7');
  await save(c); await expectMessage(c, 'Saved revision 5');
  await c.screenshot({ path: join(evidence, 'desktop.png'), fullPage: true });
  const mobileContext = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true });
  const mobile = await mobileContext.newPage(); mobile.on('pageerror', error => errors.push(error.message));
  await load(mobile);
  await mobile.screenshot({ path: join(evidence, 'mobile.png'), fullPage: true });
  for (let index = 3; index < 20; index++) await mobile.getByRole('button', { name: 'Add work item' }).click();
  await mobile.getByLabel('Item 20 name', { exact: true }).waitFor();
  await mobile.waitForFunction(() => [...document.querySelectorAll('button')].find(button => button.textContent === 'Add work item')?.disabled);
  assert(await mobile.getByRole('button', { name: 'Add work item' }).isDisabled());
  await mobile.getByLabel('Item 20 name', { exact: true }).fill('Long synthetic item '.repeat(4));
  assert(await mobile.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth));
  await mobile.screenshot({ path: join(evidence, 'mobile-max-draft.png'), fullPage: true });
  assert.equal(errors.length, 0, JSON.stringify(errors));
  console.log('PASS escaped Unicode, desktop/mobile, bounded 20-item long-label draft and no page errors');
  console.log('All seven real browser groups passed; no unsaved-draft persistence across process restart is claimed');
} finally {
  if (holder && holder.exitCode === null) { holder.kill('SIGTERM'); await once(holder, 'exit'); }
  for (const [trigger, table, fn] of [['test_hold', 'saves', 'hold_commit'], ['test_reject', 'saves', 'reject_ui_commit']]) {
    try { sql(`DROP TRIGGER IF EXISTS ${trigger} ON capacity_board.${table}; DROP FUNCTION IF EXISTS capacity_board.${fn}()`); } catch {}
  }
  if (control) await control.close();
  if (browser) await browser.close();
  if (child && child.exitCode === null) { child.kill('SIGTERM'); await once(child, 'exit'); }
}
