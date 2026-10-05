import { mkdirSync, writeFileSync } from 'node:fs';
import * as XLSX from 'xlsx';
mkdirSync('static/fixtures', { recursive: true });
writeFileSync(
  'static/fixtures/harbor-tools.csv',
  'Item Code,Description,Price,Available\nHBR101,"Copper watering can, 2L",24.50,18\nHBR102,Garden twine,6.75,42\n',
);
writeFileSync(
  'static/fixtures/needs-correction.csv',
  'Item Code,Description,Price,Available\nERR101,Hand rake,12.00,20\nERR102,Garden fork,ask,-2\n',
);
writeFileSync(
  'static/fixtures/conflicting-sku.csv',
  'Item Code,Description,Price,Available\nNEW999,New tote,9.50,15\nBASE001,Cotton market tote,12.50,40\n',
);
const workbook = XLSX.utils.book_new();
XLSX.utils.book_append_sheet(
  workbook,
  XLSX.utils.aoa_to_sheet([
    ['Item Code', 'Description', 'Price', 'Available'],
    ['FLW201', 'Woven table runner', '18.90', '12'],
    ['FLW202', 'Cotton napkins, set of four', '11.25', '30'],
  ]),
  'Catalog',
);
writeFileSync(
  'static/fixtures/meadow-textiles.xlsx',
  XLSX.write(workbook, { type: 'buffer', bookType: 'xlsx' }),
);
