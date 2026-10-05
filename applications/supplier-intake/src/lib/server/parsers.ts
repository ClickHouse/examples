import Papa from 'papaparse';
import * as XLSX from 'xlsx';
export const MAX_BYTES = 512 * 1024;
export const MAX_ROWS = 100;
export class IntakeError extends Error {}
export type Parsed = {
  format: 'csv' | 'xlsx';
  headers: string[];
  rows: Record<string, string>[];
};
export function parseUpload(bytes: Buffer, filename: string): Parsed {
  if (!bytes.length || bytes.length > MAX_BYTES)
    throw new IntakeError('Choose a non-empty file no larger than 512 KiB.');
  let matrix: string[][];
  let format: Parsed['format'];
  if (/\.csv$/i.test(filename)) {
    format = 'csv';
    let text: string;
    try {
      text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
    } catch {
      throw new IntakeError('CSV must use UTF-8 encoding.');
    }
    const parsed = Papa.parse<string[]>(text, {
      header: false,
      delimiter: ',',
      dynamicTyping: false,
      skipEmptyLines: 'greedy',
      preview: MAX_ROWS + 2,
    });
    if (parsed.errors.length)
      throw new IntakeError('CSV contains invalid quoting or inconsistent fields.');
    matrix = parsed.data;
  } else if (/\.xlsx$/i.test(filename)) {
    format = 'xlsx';
    if (bytes[0] !== 0x50 || bytes[1] !== 0x4b)
      throw new IntakeError('Choose a genuine XLSX workbook.');
    let workbook: XLSX.WorkBook;
    try {
      workbook = XLSX.read(bytes, {
        type: 'buffer',
        sheetRows: MAX_ROWS + 2,
        cellFormula: true,
      });
    } catch {
      throw new IntakeError('The XLSX workbook could not be read.');
    }
    if (workbook.SheetNames.length !== 1)
      throw new IntakeError('Use a workbook with exactly one worksheet.');
    const sheet = workbook.Sheets[workbook.SheetNames[0]];
    const range = XLSX.utils.decode_range(sheet['!fullref'] ?? sheet['!ref'] ?? 'A1');
    if (range.e.c >= 16 || range.e.r > MAX_ROWS)
      throw new IntakeError('Use at most 100 data rows and 16 columns.');
    if (
      Object.entries(sheet).some(([address, cell]) => !address.startsWith('!') && cell.f)
    )
      throw new IntakeError('Formula cells are not accepted; paste their values first.');
    matrix = XLSX.utils.sheet_to_json<string[]>(sheet, {
      header: 1,
      raw: false,
      defval: '',
      blankrows: false,
    });
  } else throw new IntakeError('Choose a CSV or XLSX file.');
  if (matrix.length < 2 || matrix.length > MAX_ROWS + 1)
    throw new IntakeError('Use between 1 and 100 data rows.');
  const headers = matrix[0].map((v) =>
    String(v)
      .trim()
      .replace(/^\uFEFF/, ''),
  );
  if (
    !headers.length ||
    headers.length > 16 ||
    headers.some((v) => !v || v.length > 80) ||
    new Set(headers).size !== headers.length
  )
    throw new IntakeError(
      'Use 1–16 distinct, non-empty column headers of at most 80 characters.',
    );
  const rows = matrix.slice(1).map((row) => {
    if (row.length !== headers.length)
      throw new IntakeError(
        'Every row must have the same number of fields as the header.',
      );
    if (row.some((v) => String(v).length > 500))
      throw new IntakeError('Each cell may contain at most 500 characters.');
    return Object.fromEntries(headers.map((header, i) => [header, String(row[i] ?? '')]));
  });
  return { format, headers, rows };
}
