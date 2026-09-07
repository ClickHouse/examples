const { test } = require("node:test");
const assert = require("node:assert/strict");
const { StockDataIngester } = require("../app");

function ingester(insert = async () => {}) {
  return new StockDataIngester({ client: { insert }, timers: false, signals: false });
}
const tick = () => new Promise((resolve) => setImmediate(resolve));

test("mixed status/data frames retain trades and quote indicators", async () => {
  const inserts = [];
  const app = ingester(async (value) => inserts.push(value));
  const sent = [];
  app.ws = { send: (message) => sent.push(JSON.parse(message)) };
  app.handleMessage(JSON.stringify([
    { ev: "status", status: "auth_success" },
    { ev: "T", sym: "MSFT", p: 100, s: 1, ds: "1.25", pt: 100, t: 101 },
    { ev: "Q", sym: "MSFT", i: [604], t: 101 },
  ]));
  app.flushBatches();
  await tick();
  assert.equal(sent.length, 2);
  assert.equal(inserts.length, 2);
  assert.equal(inserts[0].values[0].ev, undefined);
  assert.equal(inserts[0].values[0].ds, "1.25");
  assert.deepEqual(inserts[1].values[0].i, [604]);
});

test("oversized frames are split into bounded batches and queued inserts drain", async () => {
  const resolvers = [];
  const sizes = [];
  const app = ingester(({ values }) => { sizes.push(values.length); return new Promise((r) => resolvers.push(r)); });
  app.maxBatchSize = 2;
  app.maxConcurrentInserts = 1;
  app.addToBatch(Array.from({ length: 7 }, () => ({ sym: "AAPL" })), "trades");
  app.flushBatches();
  assert.equal(app.runningInserts, 1);
  assert.equal(app.insertQueue.length, 3);
  for (let i = 0; i < 4; i++) { resolvers[i](); await tick(); }
  assert.deepEqual(sizes, [2, 2, 2, 1]);
  assert.equal(app.tradesInserted, 7);
  assert.equal(app.insertQueue.length, 0);
});

test("failed inserts are counted, never reported as successfully stored", async () => {
  const app = ingester(async () => { throw new Error("fixture insert failure"); });
  await app.executeInsert([{}, {}], "trades");
  assert.equal(app.failedRecords, 2);
  assert.equal(app.tradesInserted, 0);
});

test("pause counts skipped records but continues processing authentication", () => {
  const app = ingester();
  app.isPaused = true;
  const sent = [];
  app.ws = { send: (value) => sent.push(value) };
  app.handleMessage(JSON.stringify([{ ev: "status", status: "auth_success" }, { ev: "T" }, { ev: "Q" }]));
  assert.equal(sent.length, 2);
  assert.equal(app.droppedMessages, 2);
  assert.equal(app.tradesBatch.length, 0);
});

test("reconnect scheduling is single-shot and stop cancels it", () => {
  const app = ingester();
  app.scheduleReconnect();
  const timer = app.reconnectTimer;
  app.scheduleReconnect();
  assert.equal(app.reconnectTimer, timer);
  assert.equal(app.reconnectAttempts, 1);
  app.stopIngestion();
  assert.equal(app.reconnectTimer, null);
});

test("dashboard accepts only named, parameterized queries", async () => {
  const calls = [];
  const app = ingester();
  app.client.query = async (args) => { calls.push(args); return { json: async () => [{ ticker: "AAPL" }] }; };
  const server = app.app.listen(0, "127.0.0.1");
  await new Promise((r) => server.once("listening", r));
  const url = `http://127.0.0.1:${server.address().port}/api/query`;
  const query = (body) => fetch(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
  try {
    assert.equal((await query({ query: "DROP TABLE trades" })).status, 400);
    assert.equal((await query({ query: "constructor" })).status, 400);
    assert.equal((await query({ query: "liveTableQuery", query_params: { syms: ["AAPL' OR 1"] } })).status, 400);
    const response = await query({ query: "liveTableQuery", query_params: { syms: ["AAPL"] } });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), [{ ticker: "AAPL" }]);
    assert.equal(calls.length, 1);
    assert.equal(calls[0].clickhouse_settings.readonly, 1);
  } finally { await new Promise((r) => server.close(r)); }
});
