import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { setTimeout as pause } from 'node:timers/promises';
const account = '00000000-0000-4000-8000-000000000001';
const token = JSON.parse(process.env.ACCOUNT_TOKENS)[account];
const base = 'http://127.0.0.1:3001';
const path = '/shipments/A0000000-0000-4000-8000-000000000003/transitions';
async function request() {
  const response = await fetch(base + path, { method: 'POST', headers: {
    Authorization: `Bearer ${token}`, 'Content-Type': 'application/json',
  }, body: JSON.stringify({ requestId: 'same-id', expectedRevision: 0, toStatus: 'dispatched' }),
  signal: AbortSignal.timeout(35_000) });
  assert.equal(response.status, 200);
  return response.json();
}
async function ready(child) {
  for (let attempt = 0; attempt < 60; attempt++) {
    assert.equal(child.exitCode, null, 'Server exited before becoming ready');
    try {
      const response = await fetch(base + '/shipments', { headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(2000) });
      if (response.status === 200) {
        const keys = readFileSync(`/proc/${child.pid}/environ`, 'utf8').split('\0').map(e => e.split('=')[0]);
        assert.ok(!keys.some(k => /MIGRATOR|CDC_PASSWORD|ADMIN|CLICKHOUSE_API|TEST_/.test(k)), 'Setup credentials leaked to runtime child');
        return;
      }
    } catch { /* Bounded readiness polling before the new listener is ready. */ }
    await pause(1000);
  }
  throw new Error('Server readiness timeout');
}
async function stop(child) {
  child.kill('SIGTERM');
  for (let attempt = 0; attempt < 50 && child.exitCode === null && child.signalCode === null; attempt++) await pause(100);
  assert.ok(child.exitCode !== null || child.signalCode !== null, 'Original process must exit before replacement is started');
  assert.throws(() => process.kill(child.pid, 0), { code: 'ESRCH' });
}
const launch = () => spawn('bash', ['scripts/start-runtime.sh'], {
  env: { ...process.env, PORT: '3001' }, stdio: ['ignore', 'ignore', 'inherit'],
});
let child = launch();
try {
  await ready(child);
  const first = await request();
  const firstPid = child.pid;
  await stop(child);
  child = launch();
  await ready(child);
  assert.notEqual(child.pid, firstPid);
  assert.deepEqual(await request(), first);
  const current = await fetch(base + '/shipments/a0000000-0000-4000-8000-000000000003', {
    headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(35_000),
  });
  assert.equal(current.status, 200);
  assert.equal((await current.json()).revision, 2);
  const malformed = await fetch(base + path, { method: 'POST', headers: {
    Authorization: `Bearer ${token}`, 'Content-Type': 'application/json',
  }, body: '{bad-json', signal: AbortSignal.timeout(35_000) });
  assert.equal(malformed.status, 400);
  console.log(`Runtime-only external process restart ${firstPid} -> ${child.pid}: first PID confirmed gone; uppercase retained retry returns identical 200 and current revision 2; malformed JSON returns 400`);
} finally { if (child.exitCode === null && child.signalCode === null) await stop(child); }
