import { Pool } from "pg";
import { drizzle } from "drizzle-orm/node-postgres";
export async function connectDatabase(
  urlText = process.env.DATABASE_URL,
  caPath = process.env.PG_CA_CERT_PATH,
) {
  if (!urlText) throw new Error("DATABASE_URL is required");
  const url = new URL(urlText);
  if (
    !["postgres:", "postgresql:"].includes(url.protocol) ||
    url.search ||
    url.hash
  )
    throw new Error("Use a plain Postgres URL without query parameters");
  const local = process.env.DATABASE_LOCAL === "true";
  if (local && !["127.0.0.1", "localhost", "[::1]"].includes(url.hostname))
    throw new Error("Local mode requires loopback");
  if (!local && !caPath) throw new Error("PG_CA_CERT_PATH required");
  const ca = local ? undefined : await Bun.file(caPath!).text();
  const certificates =
    ca?.match(
      /-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----/g,
    ) ?? [];
  if (!local && (certificates.length < 1 || certificates.length > 16))
    throw new Error("CA file must contain 1..16 PEM certificates");
  async function connect(trustedCa: string | undefined) {
    const pool = new Pool({
      connectionString: url.toString(),
      max: 5,
      connectionTimeoutMillis: 10000,
      idleTimeoutMillis: 30000,
      ssl: local
        ? false
        : { ca: trustedCa, servername: url.hostname, rejectUnauthorized: true },
    });
    try {
      await pool.query("SELECT 1");
      return pool;
    } catch (error) {
      await pool.end();
      throw error;
    }
  }
  try {
    return await connect(ca);
  } catch (originalError) {
    if (
      errorCode(originalError) !== "CERT_SIGNATURE_FAILURE" ||
      certificates.length < 2
    )
      throw originalError;
    // Bun1.4.2 can reject duplicate-subject roots in a rotation bundle.
    // Only supplied anchors are retried; certificate and hostname checks remain enabled.
    for (const certificate of certificates) {
      try {
        return await connect(certificate);
      } catch (error) {
        if (!CA_ERRORS.has(errorCode(error))) throw error;
      }
    }
    throw originalError;
  }
}
function errorCode(error: unknown) {
  return error !== null && typeof error === "object" && "code" in error
    ? String(error.code)
    : "";
}
const CA_ERRORS = new Set([
  "CERT_SIGNATURE_FAILURE",
  "UNABLE_TO_GET_ISSUER_CERT",
  "UNABLE_TO_GET_ISSUER_CERT_LOCALLY",
  "UNABLE_TO_VERIFY_LEAF_SIGNATURE",
  "SELF_SIGNED_CERT_IN_CHAIN",
  "DEPTH_ZERO_SELF_SIGNED_CERT",
  "CERT_HAS_EXPIRED",
  "CERT_NOT_YET_VALID",
]);

export function database(pool: Pool, counter?: { reads: number }) {
  return drizzle(pool, {
    logger: {
      logQuery(query) {
        if (/^select\b/i.test(query)) counter && counter.reads++;
      },
    },
  });
}
export type Database = ReturnType<typeof database>;
