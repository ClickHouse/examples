import { randomUUID } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import { setTimeout as delay } from "node:timers/promises";
import { closeDatabases, getClickHouse, getPostgres } from "../src/server/db";
import { createLink, updateLink } from "../src/server/service";
import { getAnalytics } from "../src/server/analytics";
import { httpsOrigin, loadSmokeEnvironment, smokeAccountId, smokeServices } from "./hosted-smoke-config";

// Run in the isolated development VM after deployment, with its local event
// worker stopped. No local flush is performed: delivery must come from Cron.
// Only temporary link IDs created by this invocation are deleted. ClickHouse
// fixture IDs are retained in a VM-private receipt for scoped ClickHouse cleanup.
class SmokeFailure extends Error {}
function check(condition: unknown, message: string): asserts condition {
  if (!condition) throw new SmokeFailure(message);
}

const linkIds: string[] = [];
let accountId: string | undefined;
let stage = "configuration";

async function request(origin: string, slug: string, method: "GET" | "HEAD", status: number, location?: string) {
  const response = await fetch(`${origin}/r/${slug}`, {
    method,
    redirect: "manual",
    headers: { "User-Agent": "ShortwaveHostedSmoke/1.0" },
    signal: AbortSignal.timeout(20_000),
  });
  check(response.status === status, `${method} on ${new URL(origin).hostname}: expected ${status}, received ${response.status}.`);
  check(response.headers.get("cache-control")?.includes("no-store"), "Redirect response must prohibit caching.");
  if (location) check(response.headers.get("location") === location, "Redirect destination differs from the saved link.");
  await response.arrayBuffer();
}

try {
  loadSmokeEnvironment();
  const customOrigin = httpsOrigin("SMOKE_CUSTOM_ORIGIN");
  const appOrigin = httpsOrigin("APP_URL");
  check(customOrigin !== appOrigin, "The custom and application origins must differ.");
  accountId = smokeAccountId();
  const hostname = new URL(customOrigin).hostname;
  const services = smokeServices();
  const cdcDatabase = process.env.CLICKHOUSE_CDC_DATABASE || process.env.CLICKHOUSE_DATABASE || "default";
  check(/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(cdcDatabase), "Invalid ClickPipes destination database.");
  // The same hosting configuration is applied to local service calls which
  // create fixtures; public requests still exercise the deployed Worker config.
  process.env.APP_URL = appOrigin;
  process.env.PUBLIC_CUSTOM_DOMAINS = hostname;
  stage = "verified domain lookup";
  const owner = await getPostgres().query<{ id: string; account_id: string; clerk_user_id: string }>(
    `SELECT d.id, d.account_id, a.clerk_user_id FROM custom_domains d
     JOIN accounts a ON a.id = d.account_id
     WHERE d.hostname = $1 AND d.account_id = $2 AND d.status = 'verified'`, [hostname, accountId],
  );
  check(owner.rows.length === 1, "The requested account must own the verified custom domain before this test.");
  const domain = owner.rows[0]!;
  accountId = domain.account_id;
  const slug = `smoke-${randomUUID()}`;
  await mkdir(".secrets", { recursive: true, mode: 0o700 });
  const receiptPath = `.secrets/hosted-${slug}.json`;
  const saveReceipt = () => writeFile(receiptPath, JSON.stringify({
    kind: "shortwave-hosted-smoke", services, accountId, domainId: domain.id, slug, linkIds,
  }, null, 2), { mode: 0o600 });
  await saveReceipt();
  console.log(`Private fixture receipt: ${receiptPath}`);
  const customDestination = "https://example.com/shortwave-hosted-custom";
  const editedDestination = "https://example.com/shortwave-hosted-edited";
  const defaultDestination = "https://example.com/shortwave-hosted-default";

  stage = "temporary link creation";
  const custom = await createLink(domain.clerk_user_id, {
    slug, domainId: domain.id, destination: customDestination, title: "Hosted domain smoke test",
  });
  linkIds.push(custom.id);
  await saveReceipt();
  const standard = await createLink(domain.clerk_user_id, {
    slug, destination: defaultDestination, title: "Hosted default smoke test",
  });
  linkIds.push(standard.id);
  await saveReceipt();

  stage = "HTTPS host-specific redirects";
  await request(customOrigin, slug, "GET", 302, customDestination);
  await request(appOrigin, slug, "GET", 302, defaultDestination);
  await request(customOrigin, slug, "HEAD", 302, customDestination);
  await request(appOrigin, slug, "HEAD", 302, defaultDestination);
  const customOnly = await createLink(domain.clerk_user_id, {
    domainId: domain.id, destination: customDestination, title: "Hosted host-isolation smoke test",
  });
  linkIds.push(customOnly.id);
  await saveReceipt();
  await request(appOrigin, customOnly.slug, "GET", 404);
  await request(customOrigin, customOnly.slug, "HEAD", 302, customDestination);
  await request(customOrigin, `absent-${randomUUID()}`, "GET", 404);
  console.log("HTTPS custom/default redirects, hostname isolation, missing links and HEAD passed.");

  stage = "immediate redirect edits and disable";
  await updateLink(domain.clerk_user_id, custom.id, { destination: editedDestination, domainId: domain.id, title: "Hosted domain smoke test" });
  await request(customOrigin, slug, "GET", 302, editedDestination);
  await updateLink(domain.clerk_user_id, custom.id, { destination: editedDestination, enabled: false, title: "Hosted edited domain smoke test" });
  await request(customOrigin, slug, "GET", 410);
  await request(customOrigin, slug, "HEAD", 410);
  console.log("Destination edits and disabled-link responses passed.");

  stage = "scheduled outbox delivery";
  const deadline = Date.now() + 90_000;
  let delivered = false;
  do {
    const pending = await getPostgres().query<{ count: number }>(
      "SELECT count(*)::int AS count FROM click_outbox WHERE account_id = $1 AND event->>'link_id' = ANY($2::text[])",
      [accountId, linkIds],
    );
    if (pending.rows[0]!.count === 0) {
      const result = await getClickHouse().query({
        query: `SELECT link_id, uniqExact(event_id) AS clicks FROM click_events
          WHERE account_id = {account:UUID} AND link_id IN {links:Array(UUID)}
          GROUP BY link_id`,
        query_params: { account: accountId, links: linkIds },
        format: "JSONEachRow",
      });
      const counts = new Map((await result.json<{ link_id: string; clicks: string | number }>()).map((row) => [row.link_id, Number(row.clicks)]));
      if (counts.get(custom.id) === 2 && counts.get(standard.id) === 1 && !counts.has(customOnly.id)) {
        delivered = true;
        break;
      }
      check([...counts.values()].reduce((sum, count) => sum + count, 0) <= 3, "Unexpected extra redirect events, possibly from HEAD or disabled requests.");
    }
    if (Date.now() < deadline) await delay(3_000);
  } while (Date.now() < deadline);
  check(delivered, "Scheduled delivery did not produce exactly three expected ClickHouse events within 90 seconds.");
  console.log("Scheduled outbox delivery and exact ClickHouse event attribution passed; HEAD/404/410 added no events.");

  stage = "analytics report";
  const report = await getAnalytics(domain.clerk_user_id, { linkId: custom.id });
  check(report.status !== "unavailable" && report.totalClicks === 2, "Custom-domain analytics did not report the two successful GET requests.");
  console.log("Custom-domain analytics reported two clicks.");

  stage = "ClickPipes metadata convergence";
  const cdcDeadline = Date.now() + 120_000;
  let metadataConverged = false;
  do {
    const result = await getClickHouse().query({
      query: `SELECT title FROM ${cdcDatabase}.cdc_links FINAL
        WHERE account_id = {account:UUID} AND id = {link:UUID} AND _peerdb_is_deleted = 0`,
      query_params: { account: accountId, link: custom.id }, format: "JSONEachRow",
    });
    const rows = await result.json<{ title: string }>();
    if (rows.length === 1 && rows[0]!.title === "Hosted edited domain smoke test") {
      metadataConverged = true;
      break;
    }
    if (Date.now() < cdcDeadline) await delay(3_000);
  } while (Date.now() < cdcDeadline);
  check(metadataConverged, "ClickPipes did not replicate the edited metadata within 120 seconds.");
  console.log("ClickPipes latest metadata matched the edited Postgres link.");
} catch (error) {
  // Raw network/database errors may contain credentials or account data.
  console.error(`Hosted domain smoke failed during ${stage}.${error instanceof SmokeFailure ? ` ${error.message}` : " Check the deployment configuration and service health."}`);
  process.exitCode = 1;
} finally {
  try {
    if (accountId && linkIds.length) {
      await getPostgres().query(
        "DELETE FROM click_outbox WHERE account_id = $1 AND event->>'link_id' = ANY($2::text[])", [accountId, linkIds],
      );
      await getPostgres().query("DELETE FROM links WHERE account_id = $1 AND id = ANY($2::uuid[])", [accountId, linkIds]);
      console.log("Temporary Postgres links and remaining fixture outbox events removed.");
    }
  } catch {
    console.error("Hosted smoke fixture cleanup failed; rerun scoped cleanup before handover.");
    process.exitCode = 1;
  } finally { await closeDatabases(); }
}
