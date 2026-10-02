import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { createHash, timingSafeEqual } from 'node:crypto';
import type { Request } from 'express';
import { required } from './config.js';

export type AccountRequest = Request & { accountId: string };
export class TokenScopes {
  private readonly entries: Array<{ digest: Buffer; accountId: string }>;
  constructor(raw: string) {
    const parsed: unknown = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error('Invalid token mapping');
    const entries = Object.entries(parsed);
    if (entries.length < 1 || entries.length > 20) throw new Error('Expected 1–20 token scopes');
    const tokens = entries.map(([, value]) => value);
    if (new Set(tokens).size !== tokens.length) throw new Error('Duplicate token');
    this.entries = entries.map(([accountId, token]) => {
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(accountId) ||
          typeof token !== 'string' || !/^[A-Za-z0-9_-]{32,256}$/.test(token)) throw new Error('Invalid token scope');
      return { digest: createHash('sha256').update(token).digest(), accountId: accountId.toLowerCase() };
    });
  }
  get accountIds(): string[] { return this.entries.map(({ accountId }) => accountId); }
  account(token: string): string | undefined {
    if (token.length > 256) return undefined;
    const digest = createHash('sha256').update(token).digest();
    let found: string | undefined;
    for (const entry of this.entries) {
      if (timingSafeEqual(entry.digest, digest)) found = entry.accountId;
    }
    return found;
  }
}
@Injectable()
export class AccountGuard implements CanActivate {
  readonly scopes = new TokenScopes(required('ACCOUNT_TOKENS'));
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<AccountRequest>();
    const header = request.headers.authorization;
    const token = typeof header === 'string' && /^Bearer [A-Za-z0-9_-]+$/.test(header) ? header.slice(7) : '';
    const accountId = this.scopes.account(token);
    if (!accountId) throw new UnauthorizedException('Invalid account token');
    request.accountId = accountId;
    return true;
  }
}
