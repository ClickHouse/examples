import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { lookup } from "node:dns/promises";
import type { SQL } from "bun";
import type { DatabaseConfig } from "../src/config";
import { createDatabase } from "../src/database";

let configuration: DatabaseConfig;
let trusted: SQL;

beforeAll(async () => {
  const url = process.env.DATABASE_URL;
  const caCertPath = process.env.PG_CA_CERT_PATH;
  if (!url || !caCertPath) throw new Error("TLS tests require DATABASE_URL and PG_CA_CERT_PATH; see tests/README.md.");
  configuration = { url, caCertPath, maxConnections: 1 };
  trusted = await createDatabase(configuration);
  // Establish the positive control first. Offline/bad-credential failures must
  // not masquerade as successful rejection of an untrusted certificate.
  const [connection] = await trusted`
    SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()
  `;
  expect(connection.ssl).toBe(true);
}, 20_000);

afterAll(async () => { await trusted?.close(); });

function verificationCodes(error: unknown, depth = 0): string[] {
  if (!error || typeof error !== "object" || depth > 5) return [];
  const details = error as { code?: unknown; cause?: unknown; errors?: unknown; errno?: unknown; message?: unknown };
  const codes = typeof details.code === "string" && /^[A-Z0-9_]+$/.test(details.code)
    ? [details.code] : [];
  // Bun 1.4.2 sometimes reports a hostname verification failure as an empty
  // Error with errno 0. Accept this only in the hostname test, after OpenSSL has
  // independently verified the real hostname over the exact numeric endpoint.
  if (error instanceof Error && details.errno === 0 && details.code === undefined &&
    (details.message === undefined || details.message === "")) {
    codes.push("BUN_OPAQUE_TLS_REJECTION_ERRNO_0");
  }
  if (details.cause) codes.push(...verificationCodes(details.cause, depth + 1));
  if (Array.isArray(details.errors)) {
    for (const nested of details.errors) codes.push(...verificationCodes(nested, depth + 1));
  }
  return codes;
}

async function rejectedConnection(config: DatabaseConfig, expected: RegExp): Promise<void> {
  let sql: SQL | undefined;
  let rejected = false;
  let codes: string[] = [];
  try {
    // Cover both an eager connection check in our factory and Bun.SQL's lazy
    // first query. A constructor call alone is not proof of TLS verification.
    sql = await createDatabase(config);
    await sql`SELECT 1 AS connected`;
  } catch (error) {
    rejected = true;
    codes = verificationCodes(error);
  } finally {
    await sql?.close();
  }
  expect(rejected).toBe(true);
  // Trust failures must carry a certificate verification code. The hostname
  // test additionally permits Bun's specific empty errno-0 error, with an
  // independent verified-TLS positive control to exclude an unreachable peer.
  // Only sanitized codes reach failure output, never driver error messages.
  expect(codes.join(" ")).toMatch(expected);
  // Establish a fresh connection with the original hostname and CA after the
  // negative probe; reusing the existing socket would not recheck its TLS path.
  const control = await createDatabase(configuration);
  try {
    const [row] = await control`SELECT 1 AS connected`;
    expect(row.connected).toBe(1);
  } finally {
    await control.close();
  }
}

async function verifyNumericEndpoint(address: string, endpoint: URL): Promise<void> {
  // Use the numeric peer address but the original expected DNS identity. This
  // performs PostgreSQL's TLS upgrade and full certificate/hostname verification
  // without sending database credentials. Ordinary TCP reachability is weaker.
  const probe = Bun.spawn([
    "openssl", "s_client", "-starttls", "postgres",
    "-connect", `${address}:${endpoint.port || "5432"}`,
    "-servername", endpoint.hostname,
    "-verify_hostname", endpoint.hostname,
    "-verify_return_error", "-CAfile", configuration.caCertPath, "-brief",
  ], { stdin: "ignore", stdout: "pipe", stderr: "pipe" });
  const deadline = setTimeout(() => probe.kill(), 10_000);
  try {
    // Drain both streams but never print them: certificates and endpoint names
    // belong in the private verification environment, not the test report.
    const [exitCode] = await Promise.all([
      probe.exited, new Response(probe.stdout).text(), new Response(probe.stderr).text(),
    ]);
    expect(exitCode).toBe(0);
  } finally {
    clearTimeout(deadline);
  }
}

describe("strict managed Postgres TLS", () => {
  test("rejects an unrelated valid CA", async () => {
    await rejectedConnection({
      ...configuration,
      caCertPath: new URL("./fixtures/untrusted-ca.pem", import.meta.url).pathname,
    }, /(?:UNABLE_TO_GET_ISSUER_CERT(?:_LOCALLY)?|UNABLE_TO_VERIFY_LEAF_SIGNATURE|SELF_SIGNED_CERT_IN_CHAIN|DEPTH_ZERO_SELF_SIGNED_CERT|CERT_UNTRUSTED|CERT_SIGNATURE_FAILURE)/);
  }, 20_000);

  test("rejects a reachable database endpoint whose hostname is not on its certificate", async () => {
    const endpoint = new URL(configuration.url);
    const { address } = await lookup(endpoint.hostname, { family: 4 });
    // Reach the same PostgreSQL endpoint by its resolved address. Managed
    // Postgres certificates identify its DNS name, not this numeric address.
    await verifyNumericEndpoint(address, endpoint);
    endpoint.hostname = address;
    const previousMode = process.env.PGSSLMODE;
    process.env.PGSSLMODE = "verify-ca";
    try {
      // An ambient weaker libpq mode must not weaken the application factory.
      await rejectedConnection(
        { ...configuration, url: endpoint.toString() },
        /(?:ERR_TLS_CERT_ALTNAME_INVALID|HOSTNAME_MISMATCH|IP_ADDRESS_MISMATCH|BUN_OPAQUE_TLS_REJECTION_ERRNO_0)/,
      );
    } finally {
      if (previousMode === undefined) delete process.env.PGSSLMODE;
      else process.env.PGSSLMODE = previousMode;
    }
  }, 30_000);
});
