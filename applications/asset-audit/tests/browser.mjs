import assert from 'node:assert/strict'
import { chromium, expect } from '@playwright/test'
import { mkdir } from 'node:fs/promises'
import { client, fixture, removeFixture, startServer, stopServer, base, request } from './helpers.mjs'
const owner = await client(true)
const evidence = process.env.TEST_EVIDENCE_DIR ?? '/tmp/asset-audit-browser'
await mkdir(evidence, { recursive: true })
let id, server, browser
try {
  id = await fixture(owner, 'October equipment browser audit')
  server = await startServer()
  browser = await chromium.launch({ headless: true })
  const context = await browser.newContext({ viewport: { width: 1512, height: 1080 } })
  const page = await context.newPage()
  const errors = []
  page.on('pageerror', (e) => errors.push(e.message))
  const openSheet = async (p) => {
    await p.goto(base)
    await p.getByText('Equipment count', { exact: true }).waitFor()
    await p.locator('.p-select').click()
    await p.getByRole('option', { name: 'October equipment browser audit' }).click()
    await p.getByText('Equipment count', { exact: true }).waitFor()
  }
  const edit = async (p, rowIndex, value) => {
    const cell = p.locator('.ag-row[row-index="' + rowIndex + '"] [col-id="counted"]')
    await cell.dblclick()
    const input = p.locator('.ag-cell-inline-editing input')
    await input.fill(String(value))
    await input.press('Enter')
  }
  await openSheet(page)
  assert.equal(await page.locator('#p-license-host').count(), 0)
  await edit(page, 0, '-1')
  await page.getByText('Enter a whole count from 0 to 1,000,000, or leave the cell empty.').waitFor()
  assert.equal(await page.getByRole('button', { name: 'Save draft', exact: true }).isDisabled(), true)
  const original = (await request('/api/stocktakes/' + id)).body
  for (let i = 0; i < original.rows.length; i++) await edit(page, i, original.rows[i].expected + (i === 0 ? -2 : i === 1 ? 1 : 0))
  await page.getByText('Unsaved changes', { exact: true }).waitFor()
  await page.screenshot({ path: evidence + '/stocktake-draft.png', fullPage: true })
  await page.getByRole('button', { name: 'Save draft', exact: true }).click()
  await page.getByText('Draft saved. Your counts are stored in Postgres.').waitFor()
  await page.reload()
  await page.getByText('Equipment count', { exact: true }).waitFor()
  await page.locator('.p-select').click()
  await page.getByRole('option', { name: 'October equipment browser audit' }).click()
  await page.getByText('Equipment count', { exact: true }).waitFor()
  assert.equal((await request('/api/stocktakes/' + id)).body.rows[0].counted, 10)
  await page.getByRole('textbox', { name: 'Filter equipment' }).fill('camera')
  await expect(page.locator('.ag-row [col-id="sku"]')).toHaveCount(1)
  await page.getByRole('textbox', { name: 'Filter equipment' }).fill('')
  await page.locator('.ag-header-cell[col-id="sku"]').click()
  await page.locator('.ag-row[row-index="2"] [col-id="sku"]').filter({ hasText: 'FAC-TOOL' }).waitFor()
  // Reload resets grid sort so row indexes represent the original equipment order.
  await openSheet(page)
  const other = await context.newPage()
  await openSheet(other)
  await edit(page, 0, 9)
  await page.getByRole('button', { name: 'Save draft', exact: true }).click()
  await page.getByText('Draft saved. Your counts are stored in Postgres.').waitFor()
  await edit(other, 0, 13)
  await other.getByRole('button', { name: 'Save draft', exact: true }).click()
  await other.getByText('Someone saved a newer revision. Reload the sheet before editing again.').waitFor()
  assert.equal(await other.getByRole('button', { name: 'Save draft', exact: true }).isDisabled(), true)
  await other.screenshot({ path: evidence + '/stocktake-conflict.png', fullPage: true })
  await other.getByRole('button', { name: 'Reload sheet', exact: true }).click()
  await other.getByRole('button', { name: 'Discard and reload', exact: true }).click()
  await other.getByText('Equipment count', { exact: true }).waitFor()
  await other.getByRole('button', { name: 'Finalize sheet', exact: true }).click()
  await other.getByRole('button', { name: 'Confirm finalization', exact: true }).click()
  await other.getByText('Count sheet finalized. These counts are now read-only.').waitFor()
  assert.equal(await other.getByRole('button', { name: 'Save draft', exact: true }).count(), 0)
  assert.equal((await request('/api/stocktakes/' + id)).body.status, 'finalized')
  await other.screenshot({ path: evidence + '/stocktake-finalized.png', fullPage: true })
  assert.deepEqual(errors, [])
  console.log('PASS real Angular/PrimeNG/AG Grid editing, invalid entry, save/reload, filter/sort, two-tab conflict and finalization')
  // An initial API failure must have visible feedback before a sheet exists.
  await page.route('**/api/stocktakes', (route) => route.fulfill({ status: 503, contentType: 'application/json', body: '{}' }))
  await page.goto(base)
  await page.getByText('The count sheets could not be loaded. Check that the API is running.').waitFor()
  console.log('PASS visible initial loading failure')
} finally {
  if (browser) await browser.close()
  if (server) await stopServer(server)
  if (id) await removeFixture(owner, id)
  await owner.end()
}
