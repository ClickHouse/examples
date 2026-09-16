import { readFile } from "node:fs/promises";
import { closeDatabases, getClickHouse, getPostgres } from "../src/server/db";
import { loadSmokeEnvironment, smokeAccountId, smokeServices, receiptLinkIds } from "./hosted-smoke-config";

// Preview by default. Deletion is restricted to one private run receipt, an
// explicitly selected account, and matching service endpoints. CDC stays intact.
let stage = "configuration";
try {
  loadSmokeEnvironment();
  const accountId = smokeAccountId();
  const services = smokeServices();
  const apply = process.argv.includes("--apply");
  const receiptIndex = process.argv.indexOf("--receipt");
  const receiptPath = receiptIndex >= 0 ? process.argv[receiptIndex + 1] : undefined;
  stage = "private fixture receipt validation";
  if (!receiptPath || !/^\.secrets\/[A-Za-z0-9_-]+\.json$/.test(receiptPath))
    throw new Error("Pass --receipt .secrets/<run>.json");
  const ids = receiptLinkIds(JSON.parse(await readFile(receiptPath, "utf8")), accountId, services);
  if (apply) {
    if (!process.env.CLICKHOUSE_MIGRATION_USERNAME || !process.env.CLICKHOUSE_MIGRATION_PASSWORD)
      throw new Error("Migration credentials required");
    process.env.CLICKHOUSE_USERNAME = process.env.CLICKHOUSE_MIGRATION_USERNAME;
    process.env.CLICKHOUSE_PASSWORD = process.env.CLICKHOUSE_MIGRATION_PASSWORD;
  }
  if (!ids.length) {
    console.log("Receipt contains no created links; no changes made.");
  } else {
    stage = "Postgres absence verification";
    const existing = await getPostgres().query("SELECT id FROM links WHERE id = ANY($1::uuid[])", [ids]);
    if (existing.rows.length) throw new Error("A fixture link still exists in Postgres; remove it through the app first");
    const pending = await getPostgres().query(
      "SELECT event_id FROM click_outbox WHERE account_id = $1 AND event->>'link_id' = ANY($2::text[]) LIMIT 1",
      [accountId, ids],
    );
    if (pending.rows.length) throw new Error("Fixture events still await delivery; wait before cleanup");
    const client = getClickHouse();
    const params = { account: accountId, links: ids };
    const countEvents = async () => {
      const result = await client.query({
        query: "SELECT count() AS count FROM click_events WHERE account_id = {account:UUID} AND link_id IN {links:Array(UUID)}",
        query_params: params, format: "JSONEachRow",
      });
      return Number((await result.json<{ count: string }>())[0]!.count);
    };
    const before = await countEvents();
    console.log(`Matched ${ids.length} deleted fixture links with ${before} ClickHouse event rows.`);
    if (apply && before) {
      stage = "scoped ClickHouse event cleanup";
      await client.command({
        query: "ALTER TABLE click_events DELETE WHERE account_id = {account:UUID} AND link_id IN {links:Array(UUID)}",
        query_params: params, clickhouse_settings: { mutations_sync: "2" },
      });
      if (await countEvents() !== 0) throw new Error("Events still present after mutation");
      console.log("Receipt-scoped fixture events removed and absence verified.");
    } else if (!apply) console.log("Preview complete. Add --apply with migration credentials to remove these fixture events.");
    else console.log("Fixture events are already absent.");
  }
} catch {
  console.error(`Hosted smoke cleanup failed during ${stage}; verify the receipt, account and service configuration. Private database details omitted.`);
  process.exitCode = 1;
} finally {
  try { await closeDatabases(); }
  catch { console.error("Database cleanup failed."); process.exitCode = 1; }
}
