import 'reflect-metadata';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { plainToInstance } from 'class-transformer';
import { validateSync } from 'class-validator';
import { TransitionDto } from '../src/dto.js';
import { assertTransition, deliveredDuration, reportRange } from '../src/domain.js';
import { TokenScopes } from '../src/auth.js';

const options = { whitelist: true, forbidNonWhitelisted: true };
test('transition input rejects control characters, forged account scope and nonnumeric revisions', () => {
  const valid = { requestId: 'dispatch-1', expectedRevision: 0, toStatus: 'dispatched' };
  assert.equal(validateSync(plainToInstance(TransitionDto, valid), options).length, 0);
  for (const input of [
    { ...valid, requestId: 'bad\n' }, { ...valid, requestId: 'bad\u0000' },
    { ...valid, expectedRevision: '0' }, { ...valid, accountId: 'foreign' },
    { ...valid, expectedRevision: -1 }, { ...valid, toStatus: 'created' },
  ]) assert.ok(validateSync(plainToInstance(TransitionDto, input), options).length > 0);
});
test('lifecycle disallows skipped and terminal transitions; duration uses accepted milliseconds', () => {
  assert.doesNotThrow(() => assertTransition('created', 'dispatched'));
  assert.doesNotThrow(() => assertTransition('dispatched', 'delivered'));
  assert.doesNotThrow(() => assertTransition('created', 'cancelled'));
  for (const from of ['created', 'delivered', 'cancelled'] as const) {
    assert.throws(() => assertTransition(from, 'delivered'));
  }
  assert.equal(deliveredDuration(new Date('2026-10-02T00:00:02.125Z'), new Date('2026-10-01T23:59:59.100Z')), '3025');
  assert.throws(() => deliveredDuration(new Date(0), new Date(1)));
  assert.throws(() => deliveredDuration(new Date(), null));
});
test('report date window is UTC-bound and rejects calendar normalization', () => {
  const now = new Date('2026-10-02T00:00:00Z');
  assert.deepEqual(reportRange(undefined, undefined, now), ['2026-09-26', '2026-10-02']);
  assert.deepEqual(reportRange('2026-09-02', '2026-10-02', now), ['2026-09-02', '2026-10-02']);
  for (const [from, to] of [['2026-09-01', '2026-10-02'], ['2026-02-30', '2026-10-02'], ['2026-10-02', '2026-10-03']]) {
    assert.throws(() => reportRange(from, to, now));
  }
});
test('token scopes retain server-derived identity and reject duplicate tokens', () => {
  const first = '00000000-0000-4000-8000-000000000001';
  const second = '00000000-0000-4000-8000-000000000002';
  const scopes = new TokenScopes(JSON.stringify({ [first]: 'a'.repeat(64), [second]: 'b'.repeat(64) }));
  assert.equal(scopes.account('a'.repeat(64)), first);
  assert.equal(scopes.account('c'.repeat(64)), undefined);
  assert.throws(() => new TokenScopes(JSON.stringify({ [first]: 'a'.repeat(64), [second]: 'a'.repeat(64) })));
});
