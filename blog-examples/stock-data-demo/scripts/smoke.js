// Uses a temporary database, removed even if verification fails.
const assert = require("node:assert/strict");
const { createClickHouseClient } = require("../config");
const { setup } = require("./setup");
const { StockDataIngester } = require("../app");
const queries = require("../queries");

async function main() {
  const database = `stock_smoke_${Date.now()}`;
  const admin = createClickHouseClient();
  const client = createClickHouseClient({ database });
  try {
    await admin.command({ query: `CREATE DATABASE ${database}` });
    await setup(client);
    const app = new StockDataIngester({ client, timers: false, signals: false });
    const t = Date.now() - 3000;
    app.handleMessage(JSON.stringify([
      { ev: "T", sym: "MSFT", i: "1", x: 4, p: 100, s: 2, ds: "2.5", pt: t - 1, c: [12], t, q: 1, z: 3 },
      { ev: "T", sym: "MSFT", i: "2", x: 4, p: 110, s: 3, c: [], t, q: 2, z: 3 },
      { ev: "Q", sym: "MSFT", bx: 4, bp: 109, bs: 100, ax: 7, ap: 111, as: 160, c: 0, i: [604], t, q: 3, z: 3 },
    ]));
    app.flushBatches();
    while (app.runningInserts || app.insertQueue.length) await new Promise((r) => setTimeout(r, 10));
    assert.equal(app.failedRecords, 0);
    assert.equal(app.tradesInserted, 2);
    assert.equal(app.quotesInserted, 1);
    const table = await (await client.query({ query: queries.liveTableQuery, query_params: { syms: ["MSFT"] }, format: "JSONEachRow" })).json();
    assert.equal(table[0].last, 110);
    assert.equal(table[0].change, 10);
    assert.equal(Number(table[0].volume), 5);
    assert.equal(table[0].bid, 109);
    assert.equal(table[0].ask, 111);
    for (const [name, query] of Object.entries(queries)) {
      const rows = await (await client.query({ query, query_params: { syms: ["MSFT"], sym: "MSFT", last: "0" }, format: "JSONEachRow" })).json();
      assert.ok(rows.length, `${name} returned no rows`);
    }
    console.log("PASS: Massive-format ingestion, optional fields, indicators, sequence ties, and all seven dashboard queries");
  } finally {
    await client.close();
    await admin.command({ query: `DROP DATABASE IF EXISTS ${database}` });
    await admin.close();
  }
}
main().catch((error) => { console.error(error); process.exitCode = 1; });
