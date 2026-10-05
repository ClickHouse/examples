import { SQL } from "bun";
import { drizzle } from "drizzle-orm/bun-sql";
export async function connectDatabase(
  urlText = process.env.DATABASE_URL,
  caPath = process.env.PG_CA_CERT_PATH,
) {
  if (!urlText) throw new Error("DATABASE_URL is required.");
  const url = new URL(urlText);
  if (
    !["postgres:", "postgresql:"].includes(url.protocol) ||
    url.search ||
    url.hash
  )
    throw new Error("Use a plain Postgres URL without query parameters.");
  const local = process.env.DATABASE_LOCAL === "true";
  if (local && !["localhost", "127.0.0.1", "[::1]"].includes(url.hostname))
    throw new Error("DATABASE_LOCAL requires a loopback host.");
  if (!local && !caPath)
    throw new Error("PG_CA_CERT_PATH is required for verified TLS.");
  url.searchParams.set("sslmode", local ? "disable" : "verify-full");
  const ca = local ? undefined : await Bun.file(caPath!).text();
  const certificates =
    ca?.match(
      /-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----/g,
    ) ?? [];
  if (!local && (certificates.length === 0 || certificates.length > 16))
    throw new Error(
      "PG_CA_CERT_PATH must contain between 1 and 16 PEM certificates.",
    );
  async function connect(trustedCa: string | undefined) {
    const client = new SQL(url, {
      max: 5,
      connectionTimeout: 10,
      idleTimeout: 30,
      maxLifetime: 1800,
      ...(local
        ? {}
        : {
            tls: {
              ca: trustedCa,
              serverName: url.hostname,
              rejectUnauthorized: true,
            },
          }),
    });
    try {
      await client`SELECT 1`;
      return { client, db: drizzle({ client }) };
    } catch (error) {
      await client.close({ timeout: 0 });
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
    // Bun can reject rotation bundles containing roots with the same subject.
    // Retry only supplied anchors; certificate and hostname verification stay enabled.
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
function errorCode(error: unknown): string {
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
export type Database = Awaited<ReturnType<typeof connectDatabase>>["db"];
