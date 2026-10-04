import { test, expect } from '@playwright/test';
import { randomUUID } from 'node:crypto';
import { spawn, type ChildProcess } from 'node:child_process';
import { once } from 'node:events';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { database, closeDatabase } from '../../app/lib/database.server';

const baseURL = process.env.APP_ORIGIN ?? 'http://127.0.0.1:3000';
const evidence = process.env.EVIDENCE_DIR ?? 'test-results';
let server: ChildProcess;
async function startServer() {
  server = spawn(process.execPath, ['--env-file=.env', './node_modules/@react-router/serve/bin.cjs', './build/server/index.js'], { stdio: 'ignore', env: process.env });
  for (let attempt = 0; attempt < 80; attempt++) {
    if (server.exitCode !== null) throw new Error('The application process exited during startup.');
    try { if ((await fetch(baseURL)).ok) return; } catch {}
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error('Application did not become ready.');
}
async function stopServer() {
  if (server && server.exitCode === null) { const exited = once(server, 'exit'); server.kill('SIGTERM'); await exited; }
}
test.beforeAll(async () => { mkdirSync(evidence, { recursive: true }); await startServer(); });
test.afterAll(async () => { await stopServer(); await closeDatabase(); });

test('record, chart, edit, stale tab, restart, filter and delete a harvest', async ({ page, context, request }) => {
  const marker = 'browser-' + randomUUID();
  let id: string | undefined;
  try {
    await page.goto('/');
    await expect(page.getByRole('heading', { name: 'A season, basket by basket.' })).toBeVisible();
    await expect(page.locator('.recharts-bar-rectangle').first()).toBeVisible();
    await page.screenshot({ path: join(evidence, 'dashboard-desktop.png'), fullPage: true });
    const originalCount = Number(await page.getByTestId('entry-count').textContent());
    await page.getByLabel('Weight (g)').fill('1');
    await page.getByLabel('Notes', { exact: true }).fill(marker);
    await page.getByRole('button', { name: 'Record harvest', exact: true }).click();
    await expect(page.getByRole('status').filter({ hasText: 'Harvest saved.' })).toBeVisible();
    await expect(page.getByTestId('entry-count')).toHaveText(String(originalCount + 1));
    const row = page.getByRole('row').filter({ hasText: marker });
    await expect(row).toBeVisible();
    await expect(row).toContainText('0.001 kg');
    const record = await database().query<{ id: string }>('SELECT id FROM harvest.entries WHERE note=$1', [marker]);
    id = record.rows[0].id;

    const secondTab = await context.newPage();
    await secondTab.goto('/');
    await row.getByRole('button', { name: /^Edit/ }).click();
    await secondTab.getByRole('row').filter({ hasText: marker }).getByRole('button', { name: /^Edit/ }).click();
    await page.getByRole('dialog').getByLabel('Weight (g)').fill('725');
    await page.getByRole('dialog').getByRole('button', { name: 'Save changes' }).click();
    await expect(page.getByRole('dialog')).not.toBeVisible();
    await secondTab.getByRole('dialog').getByLabel('Weight (g)').fill('900');
    await secondTab.getByRole('dialog').getByRole('button', { name: 'Save changes' }).click();
    await expect(secondTab.getByRole('dialog')).toContainText('changed in another tab');
    expect((await database().query('SELECT grams, version FROM harvest.entries WHERE id=$1', [id])).rows[0]).toEqual({ grams: 725, version: 2 });
    await secondTab.close();

    const previousPid = server.pid;
    await stopServer();
    await startServer();
    expect(server.pid).not.toBe(previousPid);
    writeFileSync(join(evidence, 'restart.json'), JSON.stringify({ previousPid, replacementPid: server.pid, entryId: id, observedGrams: 725 }, null, 2) + '\n');
    await page.reload();
    await expect(page.getByRole('row').filter({ hasText: marker })).toContainText('0.725 kg');

    const fields = { intent: 'create', cropId: '10000000-0000-4000-8000-000000000001', bedId: '20000000-0000-4000-8000-000000000001', harvestedOn: '2026-09-28', grams: '-1', note: marker + '-invalid' };
    // React Router selects an index route action with the ?index parameter.
    expect((await request.post('/?index', { form: fields, headers: { Origin: baseURL } })).status()).toBe(400);
    // React Router rejects foreign origins before dispatching this route action.
    expect((await request.post('/?index', { form: { ...fields, grams: '10' }, headers: { Origin: 'https://foreign.example' } })).status()).toBe(400);
    expect((await request.post('/?index', { form: { ...fields, grams: '10' } })).status()).toBe(403);
    expect((await database().query('SELECT count(*)::int AS count FROM harvest.entries WHERE note=$1', [marker + '-invalid'])).rows[0].count).toBe(0);

    await page.getByLabel(/^From/).fill('2026-09-28');
    await page.getByLabel(/^To/).fill('2026-09-28');
    await page.getByRole('button', { name: 'Apply filters' }).click();
    await expect(page).toHaveURL(/from=2026-09-28/);
    await expect(page.getByRole('row').filter({ hasText: marker })).toBeVisible();
    await page.setViewportSize({ width: 390, height: 844 });
    await page.screenshot({ path: join(evidence, 'dashboard-mobile.png'), fullPage: true });
    await page.setViewportSize({ width: 1440, height: 1100 });
    await page.getByRole('row').filter({ hasText: marker }).getByRole('button', { name: /^Delete/ }).click();
    await expect(page.getByRole('row').filter({ hasText: marker })).toHaveCount(0);
    expect((await database().query('SELECT count(*)::int AS count FROM harvest.entries WHERE id=$1', [id])).rows[0].count).toBe(0);
    await page.getByLabel(/^From/).fill('2026-11-01');
    await page.getByLabel(/^To/).fill('2026-11-02');
    await page.getByRole('button', { name: 'Apply filters' }).click();
    await expect(page.getByText('This page of the journal is empty.', { exact: false })).toBeVisible();
  } finally {
    await database().query('DELETE FROM harvest.entries WHERE note=$1 OR note=$2', [marker, marker + '-invalid']);
  }
});
