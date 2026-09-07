const { createClickHouseClient } = require("../config");
const { setup } = require("./setup");
async function main() {
  const client = createClickHouseClient();
  try {
    await setup(client);
    const now = Date.now();
    const trades = [], quotes = [];
    for (const [index, sym] of ["AAPL", "MSFT", "NVDA"].entries()) {
      for (let n = 0; n < 180; n++) {
        const t = now - (180 - n) * 1000;
        const p = 100 + index * 50 + Math.sin(n / 10) * 2;
        trades.push({ sym, i: `sample-${t}`, x: 4, p, s: 10, c: [], t, q: n, z: 3 });
        quotes.push({ sym, bx: 4, bp: p - 0.01, bs: 100, ax: 4, ap: p + 0.01, as: 100, c: 0, i: [604], t, q: n, z: 3 });
      }
    }
    await client.insert({ table: "trades", values: trades, format: "JSONEachRow" });
    await client.insert({ table: "quotes", values: quotes, format: "JSONEachRow" });
    console.log("Inserted 540 synthetic trades and 540 synthetic quotes. These are sample prices, not market data.");
  } finally { await client.close(); }
}
main().catch((error) => { console.error(error); process.exitCode = 1; });
