import { test, expect, type Page } from '@playwright/test';
import { spawn, type ChildProcess } from 'node:child_process';
import { once } from 'node:events';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { database, closeDatabase } from '../../src/lib/server/database';
const base = process.env.ORIGIN ?? 'http://127.0.0.1:3001';
const evidence = process.env.EVIDENCE_DIR ?? 'test-results';
let server: ChildProcess;
async function startServer() {
  server = spawn(process.execPath, ['--env-file=.env', 'build/index.js'], {
    stdio: 'ignore',
    env: { ...process.env, SHUTDOWN_TIMEOUT: '2' },
  });
  for (let i = 0; i < 80; i++) {
    if (server.exitCode !== null) throw new Error('Application exited during startup.');
    try {
      if ((await fetch(base)).ok) return;
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error('Application did not become ready.');
}
async function stopServer() {
  if (server && server.exitCode === null) {
    const exited = once(server, 'exit');
    server.kill('SIGTERM');
    await exited;
  }
}
test.beforeAll(async () => {
  mkdirSync(evidence, { recursive: true });
  await startServer();
});
test.afterAll(async () => {
  await stopServer();
  await closeDatabase();
});
async function upload(page: Page, filename: string) {
  await page.goto('/');
  await page
    .locator('input[type="file"]')
    .first()
    .setInputFiles(join('static/fixtures', filename));
  await page.getByRole('button', { name: /Upload 1 file/ }).click();
  await expect(page).toHaveURL(/\/batches\/[a-f0-9-]+/);
  await expect(page.getByRole('heading', { name: filename, exact: true })).toBeVisible();
  return new URL(page.url()).pathname.split('/').at(-1)!;
}
test('CSV and XLSX upload, mapped review, atomic promotion, row errors and real process restart', async ({
  page,
  request,
}) => {
  await page.goto('/');
  await expect(
    page.getByRole('heading', { name: 'A spreadsheet isn’t a catalog. Yet.' }),
  ).toBeVisible();
  await expect(page.locator('.uppy-Dashboard-inner')).toBeVisible();
  await page.screenshot({ path: join(evidence, 'receiving-desk.png'), fullPage: true });
  const csv = await upload(page, 'harbor-tools.csv');
  await page.getByLabel('Supplier name', { exact: true }).fill('Harbor Supply');
  await page.getByLabel('USD price column', { exact: true }).selectOption('Description');
  await page.getByRole('button', { name: 'Validate review', exact: true }).click();
  await expect(
    page
      .getByRole('status')
      .filter({ hasText: 'Map each field to a different existing column.' }),
  ).toBeVisible();
  await page.getByLabel('USD price column', { exact: true }).selectOption('Price');
  await page.getByRole('button', { name: 'Validate review', exact: true }).click();
  await expect(
    page.getByRole('status').filter({ hasText: 'Every row is valid.' }),
  ).toBeVisible();
  await expect(
    page.getByRole('cell', { name: 'Copper watering can, 2L', exact: true }),
  ).toBeVisible();
  await page.getByRole('tab', { name: 'Source values', exact: true }).click();
  await expect(page.getByRole('cell', { name: '24.50', exact: true })).toBeVisible();
  await page.getByRole('tab', { name: 'Reviewed rows', exact: true }).click();
  await page.getByRole('button', { name: 'Promote batch', exact: true }).click();
  await expect(
    page.getByRole('status').filter({ hasText: '2 products promoted together.' }),
  ).toBeVisible();
  await page.screenshot({ path: join(evidence, 'csv-promoted.png'), fullPage: true });
  await page.getByRole('button', { name: 'Check imported batch', exact: true }).click();
  await expect(
    page.getByRole('status').filter({ hasText: 'already imported' }),
  ).toBeVisible();
  expect(
    (
      await database().query(
        'SELECT count(*)::integer AS count FROM intake.products WHERE batch_id=$1',
        [csv],
      )
    ).rows[0].count,
  ).toBe(2);
  expect(await upload(page, 'harbor-tools.csv')).toBe(csv);
  await expect(page.getByText('promoted', { exact: true })).toBeVisible();

  const xlsx = await upload(page, 'meadow-textiles.xlsx');
  await page.getByLabel('Supplier name', { exact: true }).fill('Meadow Textiles');
  await page.getByRole('button', { name: 'Validate review', exact: true }).click();
  await expect(
    page.getByRole('status').filter({ hasText: 'Every row is valid.' }),
  ).toBeVisible();
  await expect(
    page.getByRole('cell', { name: 'Woven table runner', exact: true }),
  ).toBeVisible();
  await page.getByRole('button', { name: 'Promote batch', exact: true }).click();
  await expect(
    page.getByRole('status').filter({ hasText: '2 products promoted together.' }),
  ).toBeVisible();
  await page.screenshot({ path: join(evidence, 'xlsx-promoted.png'), fullPage: true });
  expect(
    (
      await database().query(
        'SELECT count(*)::integer AS count FROM intake.products WHERE batch_id=$1',
        [xlsx],
      )
    ).rows[0].count,
  ).toBe(2);

  const bad = await upload(page, 'needs-correction.csv');
  await page.getByRole('button', { name: 'Validate review', exact: true }).click();
  await expect(
    page.getByRole('status').filter({ hasText: '1 row needs correction.' }),
  ).toBeVisible();
  await page.getByRole('button', { name: 'Row corrections (1)', exact: true }).click();
  await expect(page.getByText(/Price must be a positive USD amount/)).toBeVisible();
  await expect(
    page.getByRole('button', { name: 'Promote batch', exact: true }),
  ).toBeDisabled();
  expect(
    (
      await request.post(`/batches/${bad}?/promote`, {
        form: { revision: '2' },
        headers: { Origin: base },
      })
    ).status(),
  ).toBe(400);
  expect(
    (
      await database().query(
        'SELECT count(*)::integer AS count FROM intake.products WHERE batch_id=$1',
        [bad],
      )
    ).rows[0].count,
  ).toBe(0);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.screenshot({
    path: join(evidence, 'row-errors-mobile.png'),
    fullPage: true,
  });
  await page.setViewportSize({ width: 1440, height: 1050 });

  const conflict = await upload(page, 'conflicting-sku.csv');
  await page.getByLabel('Supplier name', { exact: true }).fill('Willow Cooperative');
  await page.getByRole('button', { name: 'Validate review', exact: true }).click();
  await expect(
    page.getByRole('status').filter({ hasText: 'Every row is valid.' }),
  ).toBeVisible();
  await page.getByRole('button', { name: 'Promote batch', exact: true }).click();
  await expect(
    page.getByRole('status').filter({ hasText: 'No rows were imported.' }),
  ).toBeVisible();
  expect(
    (
      await database().query(
        'SELECT count(*)::integer AS count FROM intake.products WHERE batch_id=$1',
        [conflict],
      )
    ).rows[0].count,
  ).toBe(0);
  expect(
    (
      await database().query(
        "SELECT count(*)::integer AS count FROM intake.products WHERE sku='NEW999'",
      )
    ).rows[0].count,
  ).toBe(0);

  const previousPid = server.pid;
  await stopServer();
  await startServer();
  expect(server.pid).not.toBe(previousPid);
  writeFileSync(
    join(evidence, 'restart.json'),
    JSON.stringify(
      { previousPid, replacementPid: server.pid, csvBatch: csv, xlsxBatch: xlsx },
      null,
      2,
    ) + '\n',
  );
  await page.goto(`/batches/${csv}`);
  await expect(page.getByText('promoted', { exact: true })).toBeVisible();
  await page.goto(`/batches/${xlsx}`);
  await expect(page.getByText('promoted', { exact: true })).toBeVisible();
  await page.goto('/');
  await page.getByRole('tab', { name: 'Live catalog', exact: true }).click();
  await expect(
    page.getByRole('cell', { name: 'Copper watering can, 2L', exact: true }),
  ).toBeVisible();
  await expect(
    page.getByRole('cell', { name: 'Woven table runner', exact: true }),
  ).toBeVisible();
  expect(
    (
      await request.post('/api/upload', {
        multipart: {
          file: {
            name: 'ambiguous.csv',
            mimeType: 'text/csv',
            buffer: Buffer.from('A,A\nx,y\n'),
          },
        },
        headers: { Origin: base },
      })
    ).status(),
  ).toBe(400);
  expect(
    (
      await request.post('/api/upload', {
        form: {},
        headers: { Origin: 'https://foreign.example' },
      })
    ).status(),
  ).toBe(403);
  expect((await request.post('/api/upload', { form: {} })).status()).toBe(403);
  expect(
    (
      await request.post('/api/upload', {
        form: {},
        headers: { Origin: base, Host: 'foreign.example' },
      })
    ).status(),
  ).toBe(403);
});
