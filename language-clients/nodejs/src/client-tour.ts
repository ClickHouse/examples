// Client tour for @clickhouse/client (Node.js), see ../../SPEC.md for the
// contract this implementation must follow: same seven steps, same output,
// as every other language in this directory.

import { ClickHouseError, createClient } from "@clickhouse/client";

const TABLE = "readings_nodejs";
const ERROR_TABLE = "no_such_table_nodejs";

// --- 0. Environment -------------------------------------------------------
// The spec lists all six connection variables as required, even though this
// HTTP-based client only uses CLICKHOUSE_NATIVE_PORT's siblings; native/TCP
// clients (Go, C++) use that port instead. Fail fast with a clear message
// rather than letting the client surface a confusing low-level error.
const REQUIRED_ENV = [
  "CLICKHOUSE_HOST",
  "CLICKHOUSE_HTTPS_PORT",
  "CLICKHOUSE_NATIVE_PORT",
  "CLICKHOUSE_USER",
  "CLICKHOUSE_PASSWORD",
  "CLICKHOUSE_DATABASE",
] as const;

for (const name of REQUIRED_ENV) {
  if (!process.env[name]) {
    console.error(`missing required environment variable: ${name}`);
    process.exit(1);
  }
}

const {
  CLICKHOUSE_HOST,
  CLICKHOUSE_HTTPS_PORT,
  CLICKHOUSE_USER,
  CLICKHOUSE_PASSWORD,
  CLICKHOUSE_DATABASE,
} = process.env as Record<string, string>;

// The spec fixes the connection shape as discrete host/port env vars rather
// than a single connection-string variable, so the URL is assembled here
// instead of read whole from the environment.
const client = createClient({
  url: `https://${CLICKHOUSE_HOST}:${CLICKHOUSE_HTTPS_PORT}`,
  username: CLICKHOUSE_USER,
  password: CLICKHOUSE_PASSWORD,
  database: CLICKHOUSE_DATABASE,
});

// --- Row generation ---------------------------------------------------------
// Deterministic, PRNG-free rows generated purely from the row index so every
// language in the tour produces bit-identical data. Integer arithmetic first,
// a single division at the end, per the spec.

const SITES = ["amsterdam", "berlin", "london", "madrid", "paris"];
const BASE_RECORDED_AT_MS = Date.UTC(2026, 0, 1, 0, 0, 0, 0);

interface ReadingRow {
  reading_id: string;
  recorded_at: string;
  device_id: string;
  site: string;
  temp_c: number;
  humidity_pct: number | null;
  battery_pct: number;
  tags: string[];
  attributes: Record<string, string>;
}

// DateTime64(3, 'UTC') accepts 'YYYY-MM-DD HH:MM:SS.mmm' directly in JSON
// insert formats; no need for date_time_input_format = best_effort since
// this isn't an ISO-8601 string with a 'T'/'Z' separator.
function formatDateTime64Millis(ms: number): string {
  const d = new Date(ms);
  const pad = (n: number, width = 2) => String(n).padStart(width, "0");
  return (
    `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())} ` +
    `${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}:${pad(d.getUTCSeconds())}.${pad(d.getUTCMilliseconds(), 3)}`
  );
}

function generateRow(i: number): ReadingRow {
  const deviceIndex = i % 50;
  const recordedAtMs = BASE_RECORDED_AT_MS + i * 1000 + ((i * 37) % 1000);
  const tags = i % 3 === 0 ? ["calibrated"] : i % 3 === 1 ? ["calibrated", "outdoor"] : [];

  return {
    reading_id: `00000000-0000-4000-8000-${i.toString(16).padStart(12, "0")}`,
    recorded_at: formatDateTime64Millis(recordedAtMs),
    device_id: `device-${String(deviceIndex).padStart(2, "0")}`,
    site: SITES[deviceIndex % 5],
    temp_c: 15.0 + ((i * 7919) % 1997) / 100.0,
    humidity_pct: i % 10 === 0 ? null : 30.0 + ((i * 104729) % 6000) / 100.0,
    battery_pct: 100 - (i % 101),
    tags,
    attributes: { firmware: `1.${i % 4}`, model: i % 2 === 0 ? "tx-100" : "tx-200" },
  };
}

// --- Aggregate result type --------------------------------------------------

interface SiteStats {
  site: string;
  // count() is UInt64; the client returns 64-bit integers as strings by
  // default (output_format_json_quote_64bit_integers=1) to avoid precision
  // loss in JS numbers, so this is typed as a string, not a number.
  readings: string;
  avg_temp_c: number;
  max_temp_c: number;
}

async function main(): Promise<void> {
  // 1. Connect and ping.
  const versionResult = await client.query({ query: "SELECT version() AS version", format: "JSONEachRow" });
  const [{ version }] = await versionResult.json<{ version: string }>();
  console.log(`1 connect: ok, server version ${version}`);

  // 2. Create the table. DDL has no row payload, so use command() not insert().
  await client.command({ query: `DROP TABLE IF EXISTS ${CLICKHOUSE_DATABASE}.${TABLE}` });
  await client.command({
    query: `
      CREATE TABLE ${CLICKHOUSE_DATABASE}.${TABLE}
      (
          reading_id   UUID,
          recorded_at  DateTime64(3, 'UTC'),
          device_id    LowCardinality(String),
          site         LowCardinality(String),
          temp_c       Float64,
          humidity_pct Nullable(Float64),
          battery_pct  UInt8,
          tags         Array(String),
          attributes   Map(String, String)
      )
      ENGINE = MergeTree
      ORDER BY (site, device_id, recorded_at)
    `,
  });
  console.log("2 create table: ok");

  // 3. Insert 10,000 rows in 10 batches of 1,000, as plain objects in the
  // JSONEachRow representation of each column's type.
  const BATCH_SIZE = 1000;
  const BATCH_COUNT = 10;
  for (let batch = 0; batch < BATCH_COUNT; batch++) {
    const rows: ReadingRow[] = [];
    for (let i = batch * BATCH_SIZE; i < (batch + 1) * BATCH_SIZE; i++) {
      rows.push(generateRow(i));
    }
    await client.insert({ table: TABLE, values: rows, format: "JSONEachRow" });
  }
  console.log(`3 insert: ${BATCH_SIZE * BATCH_COUNT} rows in 10 batches`);

  // 4. Parameterized query: server-side binding via {name: Type} placeholders,
  // never string-formatted SQL.
  const device = "device-07";
  const minTemp = 30.0;
  const countResult = await client.query({
    query: `SELECT count() AS count FROM ${CLICKHOUSE_DATABASE}.${TABLE} WHERE device_id = {device:String} AND temp_c > {min_temp:Float64}`,
    query_params: { device, min_temp: minTemp },
    format: "JSONEachRow",
  });
  const [{ count }] = await countResult.json<{ count: string }>();
  console.log(`4 parameterized query: ${count} readings for ${device} above ${minTemp.toFixed(1)} C`);

  // 5. Stream all rows back and accumulate client-side stats without
  // buffering the full result set in memory.
  const streamResult = await client.query({
    query: `SELECT * FROM ${CLICKHOUSE_DATABASE}.${TABLE} ORDER BY recorded_at`,
    format: "JSONEachRow",
  });
  let rowCount = 0;
  let batteryTotal = 0;
  let humidityNullCount = 0;
  let tagsTotal = 0;
  for await (const rows of streamResult.stream<ReadingRow>()) {
    for (const row of rows) {
      const reading = row.json();
      rowCount++;
      batteryTotal += reading.battery_pct;
      if (reading.humidity_pct === null) humidityNullCount++;
      tagsTotal += reading.tags.length;
    }
  }
  console.log(
    `5 stream: ${rowCount} rows, battery total ${batteryTotal}, humidity null in ${humidityNullCount} rows, ${tagsTotal} tags`,
  );

  // 6. Aggregate into typed results.
  const aggregateResult = await client.query({
    query: `
      SELECT site, count() AS readings,
             round(avg(temp_c), 2) AS avg_temp_c,
             round(max(temp_c), 2) AS max_temp_c
      FROM ${CLICKHOUSE_DATABASE}.${TABLE}
      GROUP BY site ORDER BY site
    `,
    format: "JSONEachRow",
  });
  const siteStats = await aggregateResult.json<SiteStats>();
  console.log("6 aggregate: site readings avg_temp_c max_temp_c");
  for (const stats of siteStats) {
    console.log(`6 aggregate: ${stats.site} ${stats.readings} ${stats.avg_temp_c.toFixed(2)} ${stats.max_temp_c.toFixed(2)}`);
  }

  // 7. Handle a server error: catch ClickHouseError and read its .code field
  // (a string, e.g. '60' for UNKNOWN_TABLE).
  try {
    await client.query({
      query: `SELECT count() FROM ${CLICKHOUSE_DATABASE}.${ERROR_TABLE}`,
      format: "JSONEachRow",
    });
    throw new Error("expected query against a missing table to fail");
  } catch (err) {
    if (err instanceof ClickHouseError) {
      console.log(`7 error: server error code ${err.code}`);
    } else {
      throw err;
    }
  }
}

try {
  await main();
} finally {
  await client.close();
}
