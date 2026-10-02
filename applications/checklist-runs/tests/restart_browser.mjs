import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";

const evidence = process.env.EVIDENCE_DIR || "/tmp/checklist-evidence";
const fixture = JSON.parse(
  await readFile(path.join(evidence, "browser-snapshot.json"), "utf8"),
);
const issued = Math.floor(Date.now() / 1000);
const header = Buffer.from(
  JSON.stringify({ alg: "HS256", typ: "JWT" }),
).toString("base64url");
const claims = Buffer.from(
  JSON.stringify({
    role: "checklist_north",
    aud: "checklist-runs",
    iat: issued,
    exp: issued + 900,
  }),
).toString("base64url");
const body = `${header}.${claims}`;
const token = `${body}.${createHmac("sha256", process.env.PGRST_JWT_SECRET).update(body).digest("base64url")}`;
const browser = await chromium.launch({
  env: { HOME: process.env.HOME, PATH: process.env.PATH, LANG: "C.UTF-8" },
});
try {
  const page = await browser.newPage({
    viewport: { width: 1280, height: 900 },
  });
  await page.goto(process.env.UI_BASE_URL || "http://127.0.0.1:5173");
  await page.getByLabel("Operator token", { exact: true }).fill(token);
  await page.getByRole("button", { name: "Connect", exact: true }).click();
  await page
    .getByRole("button", { name: new RegExp(fixture.label) })
    .waitFor({ timeout: 30000 });
  await page.getByRole("button", { name: new RegExp(fixture.label) }).click();
  await page
    .getByText("This run is complete. Its record is retained.", { exact: true })
    .waitFor({ timeout: 30000 });
  assert.equal(
    await page.getByText("Completion confirmed", { exact: true }).count(),
    3,
  );
  await page
    .getByText("Lights and display checked", { exact: true })
    .waitFor({ timeout: 30000 });
  await page.screenshot({
    path: path.join(evidence, "restarted.png"),
    fullPage: true,
  });
  console.log(
    "Fresh browser token after actual PostgREST replacement displays the saved completed run and three immutable notes.",
  );
} finally {
  await browser.close();
}
