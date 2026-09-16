import { mkdir, writeFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { closeDatabases, getClickHouse, getPostgres } from "../src/server/db";
import { loadSmokeEnvironment, smokeAccountId, smokeServices } from "./hosted-smoke-config";

let stage = "configuration";
try {
  loadSmokeEnvironment();
  const accountId = smokeAccountId();
  const services = smokeServices();
  if (!process.env.CLICKHOUSE_MIGRATION_USERNAME || !process.env.CLICKHOUSE_MIGRATION_PASSWORD)
    throw new Error("Read-only query-log inspection requires management credentials");
  process.env.CLICKHOUSE_USERNAME = process.env.CLICKHOUSE_MIGRATION_USERNAME;
  process.env.CLICKHOUSE_PASSWORD = process.env.CLICKHOUSE_MIGRATION_PASSWORD;
  const client = getClickHouse();
  stage = "query-log schema inspection";
  const schema = await client.query({ query: "DESCRIBE TABLE system.query_log", format: "JSONEachRow" });
  const hasParameters = (await schema.json<{ name: string }>()).some((row) => row.name === "query_parameters");
  stage = "exact smoke query lookup";
  const result = await client.query({
    query: `SELECT query${hasParameters ? ", query_parameters" : ""} FROM system.query_log
      WHERE event_time >= now() - INTERVAL 2 DAY AND type = 'QueryFinish'
        AND startsWith(query, 'SELECT link_id, uniqExact(event_id) AS clicks FROM click_events')
        AND position(query, 'GROUP BY link_id') > 0
        AND position(query, 'link_id IN') > 0
        AND position(query, 'is_demo') = 0
      ORDER BY event_time DESC LIMIT 100`,
    format: "JSONEachRow",
  });
  const rows = await result.json<{ query: string; query_parameters?: Record<string, string> }>();
  const uuidPattern = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/g;
  const candidates = new Map<string, string[]>();
  for (const row of rows) {
    const parameters = row.query_parameters || {};
    const parameterAccount = parameters.account ?? parameters.param_account;
    const parameterLinks = parameters.links ?? parameters.param_links;
    let ids: string[] | undefined;
    if (parameterAccount?.replace(/^'|'$/g, "") === accountId && parameterLinks) {
      ids = parameterLinks.match(uuidPattern) || [];
      if (parameterLinks.replace(uuidPattern, "").replace(/[\s,'"\[\]]/g, "")) continue;
    } else {
      // ClickHouse logs typed parameter substitution as _CAST literals.
      // Recognize only the observed UUID and Array(UUID) forms.
      const account = row.query.match(/account_id\s*=\s*_CAST\('([0-9a-f-]{36})',\s*'UUID'\)/)?.[1]
        || row.query.match(/account_id\s*=\s*'([0-9a-f-]{36})'/)?.[1];
      const links = row.query.match(/link_id\s+IN\s+_CAST\(\[([^\]]+)\],\s*'Array\(UUID\)'\)/)?.[1]
        || row.query.match(/link_id\s+IN\s*\[([^\]]+)\]/)?.[1];
      if (account !== accountId || !links) continue;
      ids = links.match(uuidPattern) || [];
      if (links.replace(uuidPattern, "").replace(/[\s,'"]/g, "")) continue;
    }
    if (ids.length !== 3 || new Set(ids).size !== 3) continue;
    ids.sort();
    candidates.set(ids.join(","), ids);
  }
  console.log(`Found ${rows.length} exact smoke-query log rows and ${candidates.size} distinct recoverable fixture sets.`);
  if (candidates.size === 1) {
    const linkIds = [...candidates.values()][0]!;
    stage = "Postgres absence verification";
    const live = await getPostgres().query("SELECT id FROM links WHERE id = ANY($1::uuid[])", [linkIds]);
    if (live.rows.length) throw new Error("Recovered links still exist");
    await mkdir(".secrets", { recursive: true, mode: 0o700 });
    const path = `.secrets/recovered-hosted-smoke-${randomUUID()}.json`;
    await writeFile(path, JSON.stringify({ kind: "shortwave-hosted-smoke", evidence: "exact-query-log-parameters", services, accountId, linkIds }, null, 2), { mode: 0o600 });
    console.log(`Recovered one exact fixture set, verified Postgres absence, and saved a private receipt at ${path}. No database data changed.`);
  } else console.log("No unambiguous fixture receipt recovered. No database data changed.");
} catch {
  console.error(`Bounded read-only fixture recovery failed during ${stage}; private query details omitted.`);
  process.exitCode = 1;
} finally {
  try { await closeDatabases(); }
  catch { process.exitCode = 1; }
}
