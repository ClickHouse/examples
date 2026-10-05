import test from 'node:test';
import assert from 'node:assert/strict';
import * as XLSX from 'xlsx';
import { parseUpload, IntakeError } from '../src/lib/server/parsers';
import { mapRows } from '../src/lib/mapping';
const csv = 'Code,Name,USD,Qty\n001,"Tote, cotton",0.01,0\n';
test('CSV preserves quoted values and leading-zero identifiers; money stays exact', () => {
  const parsed = parseUpload(Buffer.from(csv), 'catalog.csv');
  assert.equal(parsed.rows[0].Code, '001');
  assert.equal(parsed.rows[0].Name, 'Tote, cotton');
  const reviewed = mapRows(parsed.rows, {
    batchId: '10000000-0000-4000-8000-000000000001',
    revision: 1,
    supplier: 'Cotton Co',
    sku: 'Code',
    product: 'Name',
    price: 'USD',
    stock: 'Qty',
  });
  assert.deepEqual(reviewed[0].mapped, {
    sku: '001',
    product: 'Tote, cotton',
    cents: 1,
    stock: 0,
  });
});
test('ambiguous headers, malformed rows and row limits are rejected', () => {
  for (const value of [
    'Code,Code\nA,B\n',
    'Code,Name\nA,B,C\n',
    'Code,Name\n' + Array(101).fill('A,B').join('\n'),
  ])
    assert.throws(() => parseUpload(Buffer.from(value), 'input.csv'), IntakeError);
});
test('XLSX parsing reads a genuine workbook and rejects formulas', () => {
  const workbook = XLSX.utils.book_new();
  const sheet = XLSX.utils.aoa_to_sheet([
    ['Code', 'Name', 'USD', 'Qty'],
    ['001', 'Tea towel', '8.00', '4'],
  ]);
  XLSX.utils.book_append_sheet(workbook, sheet, 'Catalog');
  assert.equal(
    parseUpload(
      XLSX.write(workbook, { type: 'buffer', bookType: 'xlsx' }),
      'catalog.xlsx',
    ).rows[0].Name,
    'Tea towel',
  );
  sheet.C2 = { t: 'n', v: 8, f: '4+4' };
  assert.throws(
    () =>
      parseUpload(
        XLSX.write(workbook, { type: 'buffer', bookType: 'xlsx' }),
        'catalog.xlsx',
      ),
    /Formula/,
  );
});
test('invalid and duplicated SKU rows remain unpromotable', () => {
  const rows = [
    { Code: 'A', Name: 'Rake', USD: '9.00', Qty: '1' },
    { Code: 'a', Name: 'Fork', USD: 'ask', Qty: '-2' },
  ];
  const reviewed = mapRows(rows, {
    batchId: '10000000-0000-4000-8000-000000000001',
    revision: 1,
    supplier: 'Tools Co',
    sku: 'Code',
    product: 'Name',
    price: 'USD',
    stock: 'Qty',
  });
  assert.ok(reviewed.every((row) => row.mapped === null));
  assert.ok(reviewed[1].errors.length >= 3);
});
