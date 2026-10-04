import test from 'node:test';
import assert from 'node:assert/strict';
import { entrySchema, filterSchema } from '../app/lib/validation';
import { enforceOrigin } from '../app/lib/security.server';
const base = { cropId: '10000000-0000-4000-8000-000000000001', bedId: '20000000-0000-4000-8000-000000000001', harvestedOn: '2026-09-28', grams: '450', note: ' Basket ' };
test('date-only inputs preserve dates and convert whole grams', () => { const value = entrySchema.parse(base); assert.equal(value.harvestedOn, base.harvestedOn); assert.equal(value.grams, 450); assert.equal(value.note, 'Basket'); });
test('reject invalid calendar dates, negative/fractional weights and long notes', () => {
  for (const patch of [{ harvestedOn: '2026-02-30' }, { grams: -1 }, { grams: '' }, { grams: 1.5 }, { note: 'x'.repeat(501) }]) assert.equal(entrySchema.safeParse({ ...base, ...patch }).success, false);
});
test('date filters are ordered and bounded', () => {
  assert.equal(filterSchema.safeParse({ from: '2026-09-30', to: '2026-09-01', cropId: '' }).success, false);
  assert.equal(filterSchema.safeParse({ from: '2020-01-01', to: '2026-09-30', cropId: '' }).success, false);
});
test('mutation trust boundary rejects foreign and absent origins', () => {
  process.env.APP_ORIGIN = 'http://127.0.0.1:3000';
  for (const origin of [undefined, 'https://example.com']) assert.throws(() => enforceOrigin(new Request('http://127.0.0.1:3000/', { method: 'POST', headers: origin ? { Origin: origin } : {} })));
  assert.doesNotThrow(() => enforceOrigin(new Request('http://127.0.0.1:3000/', { method: 'POST', headers: { Origin: 'http://127.0.0.1:3000' } })));
  assert.throws(() => enforceOrigin(new Request('http://evil.example:3000/')));
});
