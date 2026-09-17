import { SQL } from "bun";
import { validateDatabaseUrl, type DatabaseConfig } from "./config.ts";

export async function createDatabase(config: DatabaseConfig): Promise<SQL> {
  const url = validateDatabaseUrl(config.url);
  // Only this known Bun option is added internally. It overrides ambient PGSSLMODE;
  // arbitrary provider URL parameters are rejected by validateDatabaseUrl.
  url.searchParams.set("sslmode", "verify-full");
  const ca = await Bun.file(config.caCertPath).text();
  const certificates = ca.match(/-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----/g) ?? [];
  if (certificates.length === 0 || certificates.length > 16) {
    throw new Error("PG_CA_CERT_PATH must contain between 1 and 16 PEM certificates.");
  }

  async function connect(trustedCa: string): Promise<SQL> {
    const sql = new SQL(url, {
      max: config.maxConnections,
      idleTimeout: 30,
      maxLifetime: 1800,
      connectionTimeout: 10,
      tls: {
        ca: trustedCa,
        serverName: url.hostname,
        rejectUnauthorized: true,
      },
    });
    try {
      await sql`SELECT 1`;
      return sql;
    } catch (error) {
      await sql.close({ timeout: 0 });
      throw error;
    }
  }

  try {
    return await connect(ca);
  } catch (originalError) {
    if (errorCode(originalError) !== "CERT_SIGNATURE_FAILURE" || certificates.length < 2) throw originalError;
    // Bun 1.4.2 can reject a rotation bundle containing roots with the same subject.
    // Retry only the supplied trust anchors, always verifying certificate AND hostname.
    // The first successful pool retains that CA until the application restarts.
    for (const certificate of certificates) {
      try {
        return await connect(certificate);
      } catch (error) {
        // A valid anchor with the wrong hostname, a bad password, or a network error
        // must remain a failure rather than being hidden by an unrelated anchor.
        if (!CA_ERRORS.has(errorCode(error))) throw error;
      }
    }
    throw originalError;
  }
}

function errorCode(error: unknown): string {
  return error !== null && typeof error === "object" && "code" in error ? String(error.code) : "";
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
