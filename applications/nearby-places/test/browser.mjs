import assert from "node:assert/strict";
import process from "node:process";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdir } from "node:fs/promises";
import { setTimeout as delay } from "node:timers/promises";
import { chromium } from "playwright";
const source = process.env.APP_DIR;
const evidence = process.env.EVIDENCE_DIR;
assert(source && evidence, "APP_DIR and EVIDENCE_DIR are required");
await mkdir(evidence, { recursive: true });
const env = {};
for (
  const key of [
    "HOME",
    "PATH",
    "PGHOST",
    "PGPORT",
    "PGDATABASE",
    "PGUSER",
    "PGPASSWORD",
    "PGSSLROOTCERT",
  ]
) env[key] = process.env[key];
env.PORT = "4082";
let server;
let serverOutput = "";
async function start() {
  serverOutput = "";
  server = spawn("bash", ["scripts/run.sh"], {
    cwd: source,
    env,
    stdio: ["ignore", "pipe", "pipe"],
  });
  server.stdout.on("data", (data) => {
    serverOutput += data.toString();
  });
  server.stderr.on("data", (data) => {
    serverOutput += data.toString();
  });
  for (let attempt = 0; attempt < 100; attempt++) {
    if (server.exitCode !== null) throw new Error(`Server exited: ${serverOutput}`);
    try {
      if ((await fetch("http://127.0.0.1:4082/health")).status === 200) return;
    } catch { /* Startup is not yet ready. */ }
    await delay(100);
  }
  throw new Error("Server did not become ready");
}
async function stop() {
  if (!server || server.exitCode !== null || server.signalCode !== null) return;
  const exited = once(server, "exit");
  server.kill("SIGTERM");
  const timeout = setTimeout(() => server.kill("SIGKILL"), 10_000);
  const [code, signal] = await exited;
  clearTimeout(timeout);
  assert.notEqual(signal, "SIGKILL", "Graceful stop timed out");
  assert.equal(code, 0, serverOutput);
}
let browser;
let checks = 0;
async function check(name, fn) {
  await fn();
  checks++;
  console.log(`PASS ${checks}: ${name}`);
}
const url = "http://127.0.0.1:4082";
try {
  await start();
  browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1100 } });
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto(url);
  await check("initial synthetic directory is ordered by exact distance and ID", async () => {
    await page.waitForFunction(() =>
      document.querySelector("#status").textContent.startsWith("5 sample places")
    );
    assert.deepEqual(await page.locator("#results h3").allTextContents(), [
      "Anchor Cafe",
      "Courtyard Cafe",
      "Garden Library",
      "Quay Park",
      "Further Cafe",
    ]);
    assert((await page.locator("body").innerText()).includes("Synthetic directory"));
    await page.screenshot({ path: `${evidence}/desktop.png`, fullPage: true });
  });
  await check("category and limit controls filter the real API results", async () => {
    await page.getByLabel("Category", { exact: true }).selectOption("cafe");
    await page.getByRole("button", { name: "Find nearby places" }).click();
    await page.waitForFunction(() =>
      document.querySelector("#status").textContent.startsWith("3 sample places")
    );
    assert.equal(await page.locator("#results h3").count(), 3);
    await page.getByLabel("Maximum results").fill("1");
    await page.getByRole("button", { name: "Find nearby places" }).click();
    await page.waitForFunction(() =>
      document.querySelector("#status").textContent.startsWith("1 sample place")
    );
    assert.equal(await page.locator("#results h3").first().innerText(), "Anchor Cafe");
  });
  await check("dateline preset returns the opposite side within 300 meters", async () => {
    await page.getByLabel("Maximum results").fill("20");
    await page.getByRole("button", { name: "Across dateline" }).click();
    await page.waitForFunction(() =>
      document.querySelector("#status").textContent.startsWith("2 sample places")
    );
    assert.deepEqual(await page.locator("#results h3").allTextContents(), [
      "Dateline East Cafe",
      "Dateline West Park",
    ]);
    assert.equal(await page.locator(".distance strong").nth(1).innerText(), "222.6 m");
  });
  await check("empty result and mobile layout remain usable", async () => {
    await page.getByLabel("Category", { exact: true }).selectOption("library");
    await page.getByRole("button", { name: "Find nearby places" }).click();
    await page.waitForFunction(() =>
      document.querySelector("#status").textContent.startsWith("No sample places")
    );
    assert.equal(await page.locator("#results h3").count(), 0);
    await page.setViewportSize({ width: 390, height: 844 });
    await page.getByRole("button", { name: "London sample" }).click();
    await page.waitForFunction(() =>
      document.querySelector("#status").textContent.startsWith("5 sample places")
    );
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
    await page.screenshot({ path: `${evidence}/mobile.png`, fullPage: true });
  });
  const canonical = `${url}/api/nearby?longitude=0&latitude=0&radiusMeters=1200`;
  let before;
  await check(
    "native HTTP rejects malformed and SQL-shaped values and exposes no mutation route",
    async () => {
      for (
        const suffix of [
          "&category=cafe%27%20OR%20true--",
          "&longitude=1",
          "&limit=51",
          "&unexpected=1",
        ]
      ) assert.equal((await fetch(canonical + suffix)).status, 400);
      for (
        const longitude of ["NaN", "Infinity", "181", "0%3BDROP%20TABLE%20nearby_places.places"]
      ) {
        assert.equal(
          (await fetch(`${url}/api/nearby?longitude=${longitude}&latitude=0&radiusMeters=10`))
            .status,
          400,
        );
      }
      assert.equal((await fetch(`${url}/api/nearby`, { method: "POST" })).status, 405);
      assert.equal((await fetch(`${url}/api/nearby?x=${"a".repeat(2100)}`)).status, 414);
      const response = await fetch(canonical);
      assert.equal(response.status, 200);
      before = await response.json();
      assert.equal(before.places.length, 3);
    },
  );
  await check(
    "confirmed process exit and restart retain the same seeded Cloud results",
    async () => {
      const oldPid = server.pid;
      await stop();
      await start();
      assert.notEqual(server.pid, oldPid);
      assert.deepEqual(await (await fetch(canonical)).json(), before);
      await page.reload();
      await page.waitForFunction(() =>
        document.querySelector("#status").textContent.startsWith("5 sample places")
      );
      assert.deepEqual(errors, []);
    },
  );
  console.log(`Browser/HTTP acceptance: ${checks} checks passed; no browser errors`);
} finally {
  if (browser) await browser.close();
  await stop();
}
