import { loadEnvFile } from "node:process";

export const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export function loadSmokeEnvironment() {
  try { loadEnvFile(".env"); }
  catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
}

export function smokeAccountId(): string {
  const account = process.env.SMOKE_ACCOUNT_ID;
  if (!account || !uuidPattern.test(account))
    throw new Error("Set SMOKE_ACCOUNT_ID to the account UUID shown by your deployment.");
  return account;
}

export function httpsOrigin(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Set ${name} to an HTTPS origin.`);
  const url = new URL(value);
  if (url.protocol !== "https:" || url.username || url.password || url.port ||
      url.pathname !== "/" || url.search || url.hash)
    throw new Error(`${name} must be an HTTPS origin without credentials, path, or port.`);
  return url.origin;
}

// Bind private receipts to the target services as well as the fixture account.
export function smokeServices() {
  const postgres = new URL(process.env.DATABASE_URL || "");
  const clickhouse = new URL(process.env.CLICKHOUSE_URL || "");
  return {
    postgres: `${postgres.host}${postgres.pathname}`,
    clickhouse: clickhouse.origin,
    database: process.env.CLICKHOUSE_DATABASE || "default",
  };
}

export function receiptLinkIds(value: unknown, accountId: string, services: ReturnType<typeof smokeServices>): string[] {
  if (!value || typeof value !== "object") throw new Error("Invalid fixture receipt");
  const receipt = value as Record<string, unknown>;
  const recordedServices = receipt.services as Record<string, unknown> | undefined;
  if (receipt.kind !== "shortwave-hosted-smoke" || receipt.accountId !== accountId ||
      !recordedServices || Object.entries(services).some(([key, entry]) => recordedServices[key] !== entry) ||
      !Array.isArray(receipt.linkIds) || receipt.linkIds.length > 3 ||
      new Set(receipt.linkIds).size !== receipt.linkIds.length ||
      receipt.linkIds.some((id) => typeof id !== "string" || !uuidPattern.test(id)))
    throw new Error("Receipt does not match this account and deployment");
  return receipt.linkIds as string[];
}
