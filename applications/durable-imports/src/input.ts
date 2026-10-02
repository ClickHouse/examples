import { createHash } from "node:crypto";

export const MAX_ROWS = 100;
export const MAX_BYTES = 64 * 1024;
export const MAX_PENDING = 5;
export const MAX_DAILY = 50;
export const CASEY = "00000000-0000-0000-0000-000000000001";
export const MORGAN = "00000000-0000-0000-0000-000000000002";
export type Contact = { email: string; name: string };
export class ApiError extends Error {
  constructor(
    public status: number,
    public code: string,
  ) {
    super(code);
  }
}
export function uuid(value: unknown): value is string {
  return (
    typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      value,
    )
  );
}
function object(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}
function exact(value: Record<string, unknown>, keys: string[]): boolean {
  return (
    JSON.stringify(Object.keys(value).sort()) === JSON.stringify(keys.sort())
  );
}
export function normalize(input: unknown): {
  requestId: string;
  rows: Contact[];
  fingerprint: string;
} {
  if (
    !object(input) ||
    !exact(input, ["requestId", "rows"]) ||
    !uuid(input.requestId) ||
    !Array.isArray(input.rows) ||
    input.rows.length < 1 ||
    input.rows.length > MAX_ROWS
  )
    throw new ApiError(400, "invalid_import");
  if (Buffer.byteLength(JSON.stringify(input)) > MAX_BYTES)
    throw new ApiError(413, "body_too_large");
  const emails = new Set<string>();
  const rows = input.rows.map((row): Contact => {
    if (
      !object(row) ||
      !exact(row, ["email", "name"]) ||
      typeof row.email !== "string" ||
      typeof row.name !== "string" ||
      !row.name.isWellFormed()
    )
      throw new ApiError(400, "invalid_contact");
    const email = row.email.trim().toLowerCase();
    const name = row.name.normalize("NFKC").trim().replace(/\s+/gu, " ");
    if (
      email.length > 254 ||
      !/^[a-z0-9._+-]+@[a-z0-9.-]+\.[a-z]{2,63}$/.test(email) ||
      name.length === 0 ||
      [...name].length > 80 ||
      name.includes("\0") ||
      emails.has(email)
    )
      throw new ApiError(400, "invalid_contact");
    emails.add(email);
    return { email, name };
  });
  return {
    requestId: input.requestId.toLowerCase(),
    rows,
    fingerprint: createHash("sha256")
      .update(JSON.stringify(rows))
      .digest("hex"),
  };
}
