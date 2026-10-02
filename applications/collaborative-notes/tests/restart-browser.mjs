import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";
import { createPool } from "../dist-server/server/database.js";
const evidence =
  process.env.EVIDENCE_DIR || "/tmp/collaborative-notes-evidence";
const expected = JSON.parse(
  await readFile(path.join(evidence, "committed-state.json"), "utf8"),
);
const pool = createPool();
const browser = await chromium.launch({
  env: { HOME: process.env.HOME, PATH: process.env.PATH, LANG: "C.UTF-8" },
});
try {
  const row = (
    await pool.query(
      "SELECT state,revision,stored_at FROM notes.documents WHERE id=$1",
      [expected.document],
    )
  ).rows[0];
  assert.equal(row.state.toString("hex"), expected.stateHex);
  assert.equal(row.revision, expected.revision);
  assert.equal(row.stored_at.toISOString(), expected.storedAt);
  const page = await browser.newPage();
  await page.goto(process.env.UI_BASE_URL || "http://127.0.0.1:5173");
  await page.getByLabel("Workspace token").fill(process.env.WORKSPACE_TOKEN);
  await page.getByRole("button", { name: "Connect", exact: true }).click();
  await page
    .getByText("Connected and synchronized", { exact: true })
    .waitFor({ timeout: 30000 });
  const value = await page
    .locator(".cm-line")
    .evaluateAll((lines) => lines.map((line) => line.textContent).join("\n"));
  assert.equal(value, expected.text);
  await page.screenshot({
    path: path.join(evidence, "restart.png"),
    fullPage: true,
  });
  await writeFile(
    path.join(evidence, "restart-state.json"),
    JSON.stringify(
      {
        document: expected.document,
        text: value,
        stateHex: row.state.toString("hex"),
        revision: row.revision,
        storedAt: row.stored_at.toISOString(),
      },
      null,
      2,
    ),
  );
  console.log(
    "PASS exact committed Cloud binary, revision, timestamp and fresh-browser text survived actual process replacement; no reconstructed JSON document or duplicated content.",
  );
} finally {
  await browser.close();
  await pool.end();
}
