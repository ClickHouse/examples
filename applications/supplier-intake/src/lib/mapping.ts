import { z } from 'zod';
export const mappingSchema = z.object({
  batchId: z.uuid(),
  revision: z.coerce.number().int().min(1),
  supplier: z.string().trim().min(2).max(80),
  sku: z.string().min(1).max(80),
  product: z.string().min(1).max(80),
  price: z.string().min(1).max(80),
  stock: z.string().min(1).max(80),
});
export type Mapping = z.infer<typeof mappingSchema>;
export type Product = { sku: string; product: string; cents: number; stock: number };
export type ReviewedRow = {
  row: number;
  raw: Record<string, string>;
  mapped: Product | null;
  errors: string[];
};
export function mapRows(rows: Record<string, string>[], mapping: Mapping): ReviewedRow[] {
  const reviewed = rows.map((raw, index) => {
    const errors: string[] = [];
    const sku = (raw[mapping.sku] ?? '').trim().toUpperCase();
    const product = (raw[mapping.product] ?? '').trim();
    const price = (raw[mapping.price] ?? '').trim();
    const quantity = (raw[mapping.stock] ?? '').trim();
    if (!/^[A-Z0-9_-]{1,32}$/.test(sku))
      errors.push('SKU must contain 1–32 letters, digits, underscores or dashes.');
    if (!product || product.length > 120)
      errors.push('Product name must contain 1–120 characters.');
    const [whole, decimal = ''] = price.split('.');
    const cents = Number(whole) * 100 + Number(decimal.padEnd(2, '0'));
    if (!/^\d{1,6}(\.\d{1,2})?$/.test(price) || cents < 1 || cents > 99_999_999)
      errors.push('Price must be a positive USD amount with at most two decimals.');
    const stock = Number(quantity);
    if (!/^\d{1,7}$/.test(quantity) || stock > 1_000_000)
      errors.push('Stock must be a whole number between 0 and 1,000,000.');
    return {
      row: index + 2,
      raw,
      mapped: errors.length ? null : { sku, product, cents, stock },
      errors,
    };
  });
  const counts = new Map<string, number>();
  for (const row of reviewed) {
    const sku = (row.raw[mapping.sku] ?? '').trim().toUpperCase();
    counts.set(sku, (counts.get(sku) ?? 0) + 1);
  }
  for (const row of reviewed)
    if ((counts.get((row.raw[mapping.sku] ?? '').trim().toUpperCase()) ?? 0) > 1) {
      row.errors.push('SKU occurs more than once in this file.');
      row.mapped = null;
    }
  return reviewed;
}
