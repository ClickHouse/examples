import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

test('snapshot verification refuses a held fixture lock before creating a fixture or connecting', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'shortwave-cdc-lock-'));
  try {
    const deployment = join(directory, '.deployment');
    await mkdir(deployment);
    await writeFile(join(deployment, 'cdc-snapshot.lock'), 'held-by-another-process\n');
    const result = spawnSync(process.execPath, [fileURLToPath(new URL('../scripts/verify-cdc.mjs', import.meta.url)), '--await-snapshot'], {
      cwd: directory, encoding: 'utf8', timeout: 10_000,
      env: { ...process.env, DATABASE_URL: 'postgresql://unused:unused@db.example.com/postgres', PG_CA_CERT_PATH: 'must-not-be-read.pem', CLICKHOUSE_URL: 'https://unused.example.com', CLICKHOUSE_USERNAME: 'unused', CLICKHOUSE_PASSWORD: 'unused' },
    });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /CDC verification failed/);
    assert.deepEqual(await readdir(deployment), ['cdc-snapshot.lock']);
    assert.equal(await readFile(join(deployment, 'cdc-snapshot.lock'), 'utf8'), 'held-by-another-process\n');
  } finally { await rm(directory, { recursive: true, force: true }); }
});
