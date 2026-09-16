import { randomBytes, randomUUID } from "node:crypto";
import { Resolver } from "node:dns/promises";
import { isIP } from "node:net";
import { domainToASCII } from "node:url";
import { z } from "zod";
import {
  DOMAIN_CHECK_INTERVAL_MS,
  DOMAIN_VERIFICATION_LABEL,
  DOMAIN_VERIFICATION_PREFIX,
  MAX_CUSTOM_DOMAIN_LENGTH,
  MAX_CUSTOM_DOMAINS,
  type CustomDomain,
} from "../lib/custom-domains";
import { getPostgres, transaction } from "./db";
import { getAccountId, NotFoundError } from "./service";
import { isCustomDomainHosted } from "./domain-routing";

const uuid = z.string().uuid();
const DNS_TIMEOUT_MS = 5_000;
const DNS_CONCURRENCY = 8;
const missingMessage = "TXT record not found. Add the record shown, allow DNS changes to propagate, then check again.";
const mismatchMessage = "TXT value does not match. Copy the exact value shown, allow DNS changes to propagate, then check again.";
const unavailableMessage = "DNS lookup is temporarily unavailable. Try again shortly.";
const conflictMessage = "This domain cannot be verified for this account. Remove its existing verified claim or use another domain.";

export function normalizeCustomDomain(input: string): string {
  const invalid = () => new Error("Enter a public domain or subdomain, without a URL, path, or port.");
  if (typeof input !== "string" || input.length > 1024) throw invalid();
  const value = input.trim().replace(/\.$/, "");
  if (!value || /[\s\u0000-\u001f\u007f/:?#@\\%*_\[\]]/.test(value)) throw invalid();
  const hostname = domainToASCII(value).toLowerCase();
  const labels = hostname.split(".");
  // Leave room for the challenge label in the 253-byte DNS hostname limit.
  if (!hostname || hostname.length > MAX_CUSTOM_DOMAIN_LENGTH || isIP(hostname) ||
    labels.length < 2 || labels.some((label) => !/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(label)) ||
    !/[a-z]/.test(labels.at(-1)!)) throw invalid();
  // IANA special-use names plus common private-network suffixes.
  const reserved = ["localhost", "local", "test", "invalid", "example", "alt", "internal", "home", "lan", "onion", "arpa", "example.com", "example.net", "example.org"];
  if (reserved.some((suffix) => hostname === suffix || hostname.endsWith(`.${suffix}`))) throw invalid();
  return hostname;
}

type DomainRow = {
  id: string;
  hostname: string;
  verification_token: string;
  status: CustomDomain["status"];
  verified_at: Date | null;
  last_checked_at: Date | null;
  verification_error: string | null;
  verification_attempt: string | null;
  created_at: Date;
};

function toDomain(row: DomainRow): CustomDomain {
  return {
    id: row.id, hostname: row.hostname, status: row.status,
    routingReady: row.status === "verified" && isCustomDomainHosted(row.hostname),
    verificationName: `${DOMAIN_VERIFICATION_LABEL}.${row.hostname}`,
    verificationValue: `${DOMAIN_VERIFICATION_PREFIX}${row.verification_token}`,
    verifiedAt: row.verified_at ? new Date(row.verified_at).toISOString() : null,
    lastCheckedAt: row.last_checked_at ? new Date(row.last_checked_at).toISOString() : null,
    verificationError: row.verification_error,
    createdAt: new Date(row.created_at).toISOString(),
  };
}

export type TxtResolver = { resolveTxt: (hostname: string) => Promise<string[][]>; cancel: () => void };
export type TxtCheckDependencies = { createResolver?: () => TxtResolver; timeoutMs?: number };
export type TxtCheckResult = { outcome: "match" | "missing" | "mismatch" | "unavailable"; error: string | null };

/** Each check owns its resolver, so timeout cancellation cannot cancel other checks. */
export async function checkDomainTxt(name: string, value: string, dependencies: TxtCheckDependencies = {}): Promise<TxtCheckResult> {
  const timeoutMs = Math.min(DNS_TIMEOUT_MS, Math.max(1, dependencies.timeoutMs ?? DNS_TIMEOUT_MS));
  const resolver = dependencies.createResolver?.() ?? new Resolver({ timeout: timeoutMs, tries: 1 });
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    const answers = await Promise.race([
      resolver.resolveTxt(`${name}.`), // Absolute name avoids resolver search suffixes.
      new Promise<never>((_, reject) => {
        timer = setTimeout(() => {
          reject(Object.assign(new Error("DNS deadline exceeded"), { code: "ETIMEOUT" }));
          resolver.cancel();
        }, timeoutMs);
      }),
    ]);
    // Join chunks within one record, never concatenate separate TXT records.
    if (answers.some((chunks) => chunks.join("") === value)) return { outcome: "match", error: null };
    return answers.length ? { outcome: "mismatch", error: mismatchMessage } : { outcome: "missing", error: missingMessage };
  } catch (error) {
    if (["ENODATA", "ENOTFOUND"].includes((error as { code?: string }).code || ""))
      return { outcome: "missing", error: missingMessage };
    return { outcome: "unavailable", error: unavailableMessage };
  } finally { clearTimeout(timer); }
}

export async function listDomains(clerkUserId: string): Promise<CustomDomain[]> {
  const accountId = await getAccountId(clerkUserId);
  const result = await getPostgres().query<DomainRow>("SELECT * FROM custom_domains WHERE account_id = $1 ORDER BY created_at DESC, id", [accountId]);
  return result.rows.map(toDomain);
}

export async function addDomain(clerkUserId: string, input: string): Promise<CustomDomain> {
  const hostname = normalizeCustomDomain(input);
  return transaction(async (db) => {
    const accountId = await getAccountId(clerkUserId, db);
    // The account upsert holds a row lock, serializing the per-account limit.
    const existing = await db.query<DomainRow>("SELECT * FROM custom_domains WHERE account_id = $1 AND hostname = $2", [accountId, hostname]);
    if (existing.rows[0]) return toDomain(existing.rows[0]);
    const count = await db.query("SELECT count(*)::int AS count FROM custom_domains WHERE account_id = $1", [accountId]);
    if (count.rows[0].count >= MAX_CUSTOM_DOMAINS) throw new Error(`You can add up to ${MAX_CUSTOM_DOMAINS} domains. Remove one before adding another.`);
    const result = await db.query<DomainRow>(
      "INSERT INTO custom_domains (account_id, hostname, verification_token) VALUES ($1, $2, $3) RETURNING *",
      [accountId, hostname, randomBytes(32).toString("hex")],
    );
    return toDomain(result.rows[0]);
  });
}

let checksInFlight = 0;
export async function verifyDomain(clerkUserId: string, id: string, dependencies: TxtCheckDependencies = {}): Promise<CustomDomain> {
  uuid.parse(id);
  if (checksInFlight >= DNS_CONCURRENCY) throw new Error("DNS checks are busy. Try again shortly.");
  checksInFlight++;
  try {
    const accountId = await getAccountId(clerkUserId);
    const attempt = randomUUID();
    const row = await transaction(async (db) => {
      const result = await db.query<DomainRow>(
        `UPDATE custom_domains SET last_checked_at = clock_timestamp(), verification_attempt = $3
         WHERE account_id = $1 AND id = $2
           AND (last_checked_at IS NULL OR last_checked_at <= clock_timestamp() - ($4::int * interval '1 millisecond'))
         RETURNING *`, [accountId, id, attempt, DOMAIN_CHECK_INTERVAL_MS],
      );
      if (result.rows[0]) return result.rows[0];
      const owned = await db.query("SELECT id FROM custom_domains WHERE account_id = $1 AND id = $2", [accountId, id]);
      if (!owned.rows[0]) throw new NotFoundError();
      throw new Error("Wait 10 seconds between DNS checks.");
    });
    const domain = toDomain(row);
    // DNS runs after the reservation commits; no database lock is held during I/O.
    const result = await checkDomainTxt(domain.verificationName, domain.verificationValue, dependencies);
    return await transaction(async (db) => {
      await db.query("SAVEPOINT domain_verification");
      let updated;
      try {
        updated = await db.query<DomainRow>(
          `UPDATE custom_domains SET
             status = CASE WHEN $4 = 'unavailable' THEN status WHEN $4 = 'match' THEN 'verified' ELSE 'pending' END,
             verified_at = CASE WHEN $4 = 'unavailable' THEN verified_at WHEN $4 = 'match' THEN COALESCE(verified_at, clock_timestamp()) ELSE NULL END,
             verification_error = $5
           WHERE account_id = $1 AND id = $2 AND verification_attempt = $3 RETURNING *`,
          [accountId, id, attempt, result.outcome, result.error],
        );
      } catch (error) {
        if ((error as { code?: string }).code !== "23505") throw error;
        await db.query("ROLLBACK TO SAVEPOINT domain_verification");
        updated = await db.query<DomainRow>(
          "UPDATE custom_domains SET verification_error = $4 WHERE account_id = $1 AND id = $2 AND verification_attempt = $3 RETURNING *",
          [accountId, id, attempt, conflictMessage],
        );
      }
      if (updated.rows[0]) return toDomain(updated.rows[0]);
      // A later attempt wins, and deletion must never be undone by an old check.
      const current = await db.query<DomainRow>("SELECT * FROM custom_domains WHERE account_id = $1 AND id = $2", [accountId, id]);
      if (!current.rows[0]) throw new NotFoundError();
      return toDomain(current.rows[0]);
    });
  } finally { checksInFlight--; }
}

export async function removeDomain(clerkUserId: string, id: string): Promise<void> {
  uuid.parse(id);
  const accountId = await getAccountId(clerkUserId);
  try {
    const result = await getPostgres().query("DELETE FROM custom_domains WHERE account_id = $1 AND id = $2 RETURNING id", [accountId, id]);
    if (!result.rows[0]) throw new NotFoundError();
  } catch (error) {
    const constraintError = error as { code?: string; constraint?: string };
    // RESTRICT may report restrict_violation, while FK checks report
    // foreign_key_violation. Only translate this domain-link constraint.
    if (["23001", "23503"].includes(constraintError.code || "") &&
      constraintError.constraint === "links_owned_domain_fk") {
      throw new Error("This domain has links and cannot be removed, including when its links are disabled.");
    }
    throw error;
  }
}
