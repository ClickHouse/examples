import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import { mkdir } from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";

const evidence = process.env.EVIDENCE_DIR || "/tmp/checklist-evidence";
const base = process.env.UI_BASE_URL || "http://127.0.0.1:5173";
const secret = process.env.PGRST_JWT_SECRET;
assert.ok(
  secret && secret.length >= 64,
  "Export the private fixture signing secret for this helper only.",
);
await mkdir(evidence, { recursive: true });

function token(role, issued = Math.floor(Date.now() / 1000), seconds = 900) {
  const header = Buffer.from(
    JSON.stringify({ alg: "HS256", typ: "JWT" }),
  ).toString("base64url");
  const payload = Buffer.from(
    JSON.stringify({
      role,
      aud: "checklist-runs",
      iat: issued,
      exp: issued + seconds,
    }),
  ).toString("base64url");
  const body = `${header}.${payload}`;
  return `${body}.${createHmac("sha256", secret).update(body).digest("base64url")}`;
}

function deferred() {
  let resolve;
  const promise = new Promise((done) => {
    resolve = done;
  });
  return { promise, resolve };
}

async function connect(page, value) {
  await page.goto(base);
  await page.getByLabel("Operator token", { exact: true }).fill(value);
  await page.getByRole("button", { name: "Connect", exact: true }).click();
  await page
    .getByRole("heading", { name: "Start a run", exact: true })
    .waitFor({ timeout: 30000 });
}

async function ready(page) {
  await page
    .getByLabel("Checklist", { exact: true })
    .locator("option")
    .first()
    .waitFor({ state: "attached", timeout: 30000 });
  await page
    .getByRole("button", { name: "Start run", exact: true })
    .waitFor({ timeout: 30000 });
}

const browser = await chromium.launch({
  env: { HOME: process.env.HOME, PATH: process.env.PATH, LANG: "C.UTF-8" },
});
const northToken = token("checklist_north");
const southToken = token("checklist_south");
const desktop = await browser.newContext({
  viewport: { width: 1280, height: 900 },
});
const mobile = await browser.newContext({
  viewport: { width: 390, height: 844 },
  isMobile: true,
  deviceScaleFactor: 1,
});
const a = await desktop.newPage();
const b = await mobile.newPage();
const unique = Date.now().toString();
const northLabel = `Browser opening ${unique}`;
const southLabel = `Browser closing ${unique}`;
await desktop.tracing.start({
  screenshots: true,
  snapshots: true,
  sources: true,
});

try {
  await connect(a, northToken);
  await ready(a);
  await a
    .getByLabel("Checklist", { exact: true })
    .selectOption("10000000-0000-4000-8000-000000000001");
  await a.getByLabel("Run label", { exact: true }).fill(northLabel);
  const requests = [];
  const committedStart = deferred();
  let firstStart = true;
  let savedRunId;
  await a.route("**/api/rpc/start_run", async (route) => {
    requests.push(route.request().postDataJSON());
    if (firstStart) {
      firstStart = false;
      const response = await route.fetch();
      assert.equal(response.status(), 200);
      savedRunId = (await response.json()).run_id;
      assert.equal(typeof savedRunId, "string");
      await route.abort("failed");
      committedStart.resolve();
    } else {
      await route.continue();
    }
  });
  await a.getByRole("button", { name: "Start run", exact: true }).click();
  await committedStart.promise;
  await a
    .getByRole("button", { name: "Retry same action", exact: true })
    .waitFor({ timeout: 30000 });
  assert.ok(await a.getByLabel("Run label", { exact: true }).isDisabled());
  await a
    .getByRole("button", { name: "Retry same action", exact: true })
    .click();
  await a
    .getByRole("heading", { name: northLabel, exact: true })
    .waitFor({ timeout: 30000 });
  assert.equal(requests.length, 2);
  assert.deepEqual(requests[0], requests[1]);
  console.log(
    "Ambiguous start committed, then same captured UUID/payload replayed; no automatic new key.",
  );

  const completionCommitted = deferred();
  const releaseCompletion = deferred();
  const refreshHeld = deferred();
  const releaseRefresh = deferred();
  let holdRefresh = false;
  let firstCompletion = true;
  await a.route("**/api/rpc/complete_step", async (route) => {
    if (!firstCompletion) return route.continue();
    firstCompletion = false;
    const response = await route.fetch();
    assert.equal(response.status(), 200);
    completionCommitted.resolve();
    await releaseCompletion.promise;
    holdRefresh = true;
    await route.fulfill({ response });
  });
  await a.route("**/api/runs?**", async (route) => {
    if (!holdRefresh) return route.continue();
    holdRefresh = false;
    const response = await route.fetch();
    refreshHeld.resolve();
    await releaseRefresh.promise;
    await route.fulfill({ response });
  });
  await a
    .getByLabel("Completion note (optional)")
    .first()
    .fill("Lights and display checked");
  await a.getByRole("button", { name: "Complete step 1", exact: true }).click();
  await completionCommitted.promise;
  assert.equal(
    await a.getByText("Completion confirmed", { exact: true }).count(),
    0,
  );
  assert.ok(
    await a
      .getByRole("button", { name: "Complete step 2", exact: true })
      .isDisabled(),
  );
  releaseCompletion.resolve();
  await refreshHeld.promise;
  assert.ok(
    await a
      .getByRole("button", { name: "Complete step 2", exact: true })
      .isDisabled(),
  );
  releaseRefresh.resolve();
  await a
    .getByText("Completion confirmed", { exact: true })
    .first()
    .waitFor({ timeout: 30000 });
  for (const number of [2, 3]) {
    await a
      .getByRole("button", { name: `Complete step ${number}`, exact: true })
      .click();
    await a
      .getByText("Completion confirmed", { exact: true })
      .nth(number - 1)
      .waitFor({ timeout: 30000 });
  }
  await a
    .getByText("This run is complete. Its record is retained.", { exact: true })
    .waitFor({ timeout: 30000 });
  assert.equal(await a.getByRole("progressbar").getAttribute("value"), "3");
  assert.equal(
    await a.evaluate(() => localStorage.length + sessionStorage.length),
    0,
  );
  assert.ok(!a.url().includes(northToken));
  console.log(
    "No optimistic completion: controls stay pending through invalidation; all three confirmed steps are durable.",
  );
  await a.screenshot({
    path: path.join(evidence, "desktop.png"),
    fullPage: true,
  });

  await connect(b, southToken);
  await ready(b);
  await b.getByLabel("Run label", { exact: true }).fill(southLabel);
  await b.getByRole("button", { name: "Start run", exact: true }).click();
  await b
    .getByRole("heading", { name: southLabel, exact: true })
    .waitFor({ timeout: 30000 });
  assert.equal(await b.getByText(northLabel, { exact: true }).count(), 0);
  await b.screenshot({
    path: path.join(evidence, "mobile.png"),
    fullPage: true,
  });
  assert.ok(
    await b.evaluate(() => document.documentElement.scrollWidth <= innerWidth),
  );
  console.log(
    "Second browser context sees its own scope; mobile layout fits the viewport.",
  );

  const oldReadCaptured = deferred();
  const releaseOldRead = deferred();
  await a.route("**/api/rpc/list_runs?**", async (route) => {
    if (route.request().headers().authorization !== `Bearer ${northToken}`)
      return route.continue();
    const response = await route.fetch();
    const rows = await response.json();
    assert.ok(rows.some((row) => row.label === northLabel));
    oldReadCaptured.resolve();
    await releaseOldRead.promise;
    try {
      await route.fulfill({ response });
    } catch {
      /* The consumed AbortSignal can cancel the old route. */
    }
  });
  await a.getByRole("button", { name: "Refresh", exact: true }).click();
  await oldReadCaptured.promise;
  await a.getByRole("button", { name: "Disconnect", exact: true }).click();
  await a.getByLabel("Operator token", { exact: true }).fill(southToken);
  await a.getByRole("button", { name: "Connect", exact: true }).click();
  await a
    .getByRole("button", { name: new RegExp(southLabel) })
    .waitFor({ timeout: 30000 });
  releaseOldRead.resolve();
  await a.waitForTimeout(400);
  assert.equal(await a.getByText(northLabel, { exact: true }).count(), 0);
  assert.equal(
    await a.getByText("Lights and display checked", { exact: true }).count(),
    0,
  );
  console.log(
    "Actual old-scope HTTP read captured before switch and released afterward; fresh cache never displays old run/notes.",
  );

  const expired = await browser.newContext({
    viewport: { width: 1100, height: 800 },
  });
  const expiredPage = await expired.newPage();
  await connect(
    expiredPage,
    token("checklist_north", Math.floor(Date.now() / 1000) - 180, 60),
  );
  await expiredPage.getByRole("alert").waitFor({ timeout: 30000 });
  assert.match(
    await expiredPage.getByRole("alert").innerText(),
    /invalid or expired/,
  );
  await expired.close();
  console.log(
    "Expired token produces an actionable connection error; tokens are never stored in browser persistence.",
  );

  // Preserve only nonsecret identifiers for the separate real process-restart check.
  const { writeFile } = await import("node:fs/promises");
  await writeFile(
    path.join(evidence, "browser-snapshot.json"),
    JSON.stringify(
      { run_id: savedRunId, label: northLabel, request: requests[0] },
      null,
      2,
    ),
  );
  await desktop.tracing.stop();
  console.log("Browser workflow passed.");
} catch (error) {
  await a
    .screenshot({ path: path.join(evidence, "failed.png"), fullPage: true })
    .catch(() => {});
  await desktop.tracing
    .stop({ path: path.join(evidence, "failed-trace.zip") })
    .catch(() => {});
  throw error;
} finally {
  await browser.close();
}
