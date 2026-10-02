import { createHash, createHmac, timingSafeEqual } from 'node:crypto';
import { sql, type Kysely } from 'kysely';
import type { Database } from './database.js';
export class BadRequest extends Error {}
export interface Filters { q: string; category: string | null; min: number; max: number }
interface Cursor { v: 1; filters: string; price: number; id: string }
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export function filterKey(filters: Filters): string {
  return createHash('sha256').update(JSON.stringify(filters)).digest('hex');
}
function signature(payload: string, secret: string): Buffer {
  return createHmac('sha256', secret).update(payload).digest();
}
export function encodeCursor(cursor: Cursor, secret: string): string {
  const payload = Buffer.from(JSON.stringify(cursor)).toString('base64url');
  return `${payload}.${signature(payload, secret).toString('base64url')}`;
}
function decodeCursor(value: string, filters: Filters, secret: string): Cursor {
  try {
    const parts = value.split('.');
    const [payload, mac] = parts;
    if (parts.length !== 2 || !payload || !mac || !/^[A-Za-z0-9_-]+$/.test(payload)
      || !/^[A-Za-z0-9_-]{43}$/.test(mac)) throw new Error();
    const received = Buffer.from(mac, 'base64url');
    const expected = signature(payload, secret);
    if (received.length !== expected.length || !timingSafeEqual(received, expected)) throw new Error();
    const cursor = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')) as Cursor;
    if (cursor.v !== 1 || cursor.filters !== filterKey(filters) || !Number.isInteger(cursor.price)
      || cursor.price < 0 || cursor.price > 100000000 || typeof cursor.id !== 'string' || !uuid.test(cursor.id)) throw new Error();
    return cursor;
  } catch { throw new BadRequest('Invalid cursor or changed filters'); }
}
export interface Query { q?: string; category?: string; min_price?: number; max_price?: number; limit?: number; cursor?: string }
export async function listProducts(db: Kysely<Database>, input: Query, secret: string) {
  const filters: Filters = { q: (input.q ?? '').trim().replace(/\s+/g, ' ').toLowerCase(),
    category: input.category ?? null, min: input.min_price ?? 0, max: input.max_price ?? 100000000 };
  if (filters.min > filters.max) throw new BadRequest('min_price must not exceed max_price');
  const limit = input.limit ?? 20;
  let query = db.selectFrom('products').select(['id', 'sku', 'name', 'description', 'category', 'price_pence'])
    .where('active', '=', true).where('price_pence', '>=', filters.min).where('price_pence', '<=', filters.max);
  if (filters.category) query = query.where('category', '=', filters.category);
  if (filters.q) query = query.where(sql<boolean>`search_document @@ plainto_tsquery('english', ${filters.q})`);
  if (input.cursor) {
    const cursor = decodeCursor(input.cursor, filters, secret);
    query = query.where(sql<boolean>`(price_pence, id) > (${cursor.price}, ${cursor.id}::uuid)`);
  }
  const rows = await query.orderBy('price_pence').orderBy('id').limit(limit + 1).execute();
  const items = rows.slice(0, limit);
  const last = items.at(-1);
  return { items, currency: 'GBP', next_cursor: rows.length > limit && last
    ? encodeCursor({ v: 1, filters: filterKey(filters), price: last.price_pence, id: last.id }, secret) : null };
}
