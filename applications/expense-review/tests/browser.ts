import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdir } from "node:fs/promises";
import pg from "pg";
import { chromium } from "@playwright/test";
import { connection } from "../src/server/db";
const origin = process.env.APP_ORIGIN ?? "http://127.0.0.1:4332",
  evidence = process.env.EVIDENCE_DIR ?? "test-artifacts";
await mkdir(evidence, { recursive: true });
const owner = new pg.Pool(
  connection({
    user: process.env.DB_OWNER_USER,
    password: process.env.DB_OWNER_PASSWORD,
  }),
);
const server = spawn(
  process.execPath,
  [
    "node_modules/next/dist/bin/next",
    "start",
    "--hostname",
    "127.0.0.1",
    "--port",
    "4332",
  ],
  { env: process.env, stdio: ["ignore", "pipe", "pipe"] },
);
await new Promise<void>((resolve, reject) => {
  server.stdout!.on("data", (chunk) => {
    if (String(chunk).includes("Ready")) resolve();
  });
  server.once("exit", (code) => reject(new Error("server " + code)));
});
const browser = await chromium.launch({ headless: true });
const startingRevision = (
  await owner.query("SELECT revision FROM claims WHERE id=1")
).rows[0].revision;
try {
  const context = await browser.newContext({
      viewport: { width: 1450, height: 1100 },
    }),
    page = await context.newPage();
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.goto(origin);
  await page
    .getByText("500 matching · 500 loaded · 500 total saved claims", {
      exact: true,
    })
    .waitFor();
  const mounted = await page.locator("tr[data-claim-id]").count();
  assert.ok(mounted > 0 && mounted < 40);
  console.log("500 loaded claims render only", mounted, "virtual rows");
  await page.locator(".claims-scroll").evaluate((e) => {
    e.scrollTop = e.scrollHeight;
  });
  await page.getByRole("button", { name: "#500", exact: true }).waitFor();
  assert.ok((await page.locator("tr[data-claim-id]").count()) < 40);
  await page.locator("#search").fill("Morgan");
  await page
    .getByText("63 matching · 500 loaded · 500 total saved claims", {
      exact: true,
    })
    .waitFor();
  await page.locator("#search").fill("");
  await page
    .getByText("500 matching · 500 loaded · 500 total saved claims", {
      exact: true,
    })
    .waitFor();
  await page.getByRole("button", { name: "Amount", exact: true }).click();
  await page.waitForTimeout(200);
  const firstId = Number(
    await page
      .locator("tr[data-claim-id]")
      .first()
      .getAttribute("data-claim-id"),
  );
  const maximum = (
    await owner.query(
      "SELECT MAX(total)::integer AS total FROM (SELECT SUM(amount_cents) AS total FROM line_items GROUP BY claim_id) totals",
    )
  ).rows[0].total;
  const firstTotal = (
    await owner.query(
      "SELECT SUM(amount_cents)::integer AS total FROM line_items WHERE claim_id=$1",
      [firstId],
    )
  ).rows[0].total;
  assert.equal(firstTotal, maximum);
  await page.getByRole("button", { name: "Amount ↓", exact: true }).click();
  await page.waitForTimeout(200);
  const ascendingId = Number(
    await page
      .locator("tr[data-claim-id]")
      .first()
      .getAttribute("data-claim-id"),
  );
  const minimum = (
    await owner.query(
      "SELECT MIN(total)::integer AS total FROM (SELECT SUM(amount_cents) AS total FROM line_items GROUP BY claim_id) totals",
    )
  ).rows[0].total;
  const ascendingTotal = (
    await owner.query(
      "SELECT SUM(amount_cents)::integer AS total FROM line_items WHERE claim_id=$1",
      [ascendingId],
    )
  ).rows[0].total;
  assert.equal(ascendingTotal, minimum);
  await page.screenshot({
    path: evidence + "/virtual-table.png",
    fullPage: true,
  });
  await page.locator("#search").fill("claim 1");
  await page.getByRole("button", { name: "#1", exact: true }).click();
  await page
    .getByRole("dialog")
    .getByText("Morgan Reed", { exact: true })
    .waitFor();
  const stale = await context.newPage();
  await stale.goto(origin);
  await stale.getByRole("button", { name: "#1", exact: true }).click();
  await stale
    .getByRole("dialog")
    .getByText("Morgan Reed", { exact: true })
    .waitFor();
  await page.locator("#amount-0").fill("-1");
  await page
    .getByRole("button", { name: "Save amendment", exact: true })
    .click();
  await page
    .getByRole("dialog")
    .getByText(/Too small/)
    .waitFor();
  await page.locator("#amount-0").fill("4500");
  await page.locator("#memo").fill("Reviewed workshop travel amendment");
  await page
    .getByRole("button", { name: "Save amendment", exact: true })
    .click();
  await page
    .getByText("Claim amended. Review its new pending revision.", {
      exact: true,
    })
    .waitFor();
  await stale.locator("#reason").fill("Checked receipts for original revision");
  await stale
    .getByRole("button", { name: "Record decision", exact: true })
    .click();
  await stale.getByRole("alert").waitFor();
  assert.match(
    (await stale.getByRole("alert").textContent()) ?? "",
    /changed after you loaded/,
  );
  await stale
    .getByRole("button", {
      name: "Reload saved revision (discard draft)",
      exact: true,
    })
    .click();
  await stale
    .getByRole("dialog")
    .getByText(`Travel · revision ${startingRevision + 1}`, { exact: true })
    .waitFor();
  await page.locator("#reason").fill("");
  await page
    .getByRole("button", { name: "Record decision", exact: true })
    .click();
  await page
    .getByRole("dialog")
    .getByText(/Too small/)
    .waitFor();
  await page
    .locator("#reason")
    .fill("Receipts checked against workshop policy");
  await page
    .getByRole("button", { name: "Record decision", exact: true })
    .click();
  await page
    .getByText("Decision saved with the reviewed line snapshot.", {
      exact: true,
    })
    .waitFor();
  await page
    .getByText("Claim description: Reviewed workshop travel amendment", {
      exact: true,
    })
    .waitFor();
  await page.screenshot({
    path: evidence + "/reviewed-claim.png",
    fullPage: true,
  });
  const history = (
    await owner.query(
      "SELECT reviewed_revision,total_cents,memo_snapshot,line_snapshot FROM decisions WHERE claim_id=1",
    )
  ).rows;
  assert.equal(history.length, 1);
  assert.equal(history[0].reviewed_revision, startingRevision + 1);
  assert.equal(history[0].memo_snapshot, "Reviewed workshop travel amendment");
  assert.equal(history[0].total_cents, 4930);
  await page.reload();
  await page.getByRole("button", { name: "#1", exact: true }).click();
  await page
    .getByText("Claim description: Reviewed workshop travel amendment", {
      exact: true,
    })
    .waitFor();
  assert.deepEqual(errors, []);
  console.log(
    "Actual Table9 filtering/sort/selection, Virtual scroll, shadcn/RHF errors and saved tRPC decision/history/reload/conflict passed",
  );
} finally {
  await owner.query("DELETE FROM decisions WHERE claim_id=1");
  await owner.query(
    "UPDATE claims SET memo='Client workshop travel — claim 1',status='pending',revision=revision+1 WHERE id=1",
  );
  await owner.query(
    "UPDATE line_items SET amount_cents=1375 WHERE claim_id=1 AND position=0",
  );
  await owner.end();
  await browser.close();
  await new Promise<void>((resolve) => {
    server.once("exit", () => resolve());
    server.kill("SIGTERM");
  });
}
