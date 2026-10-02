import assert from "node:assert/strict";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";
const evidence =
  process.env.EVIDENCE_DIR || "/tmp/collaborative-notes-evidence";
await mkdir(evidence, { recursive: true });
const token = process.env.WORKSPACE_TOKEN;
if (!token) throw new Error("Set private WORKSPACE_TOKEN.");
const cleanEnv = {
  HOME: process.env.HOME,
  PATH: process.env.PATH,
  LANG: "C.UTF-8",
};
const first = await chromium.launch({ env: cleanEnv });
const second = await chromium.launch({ env: cleanEnv });
async function text(page) {
  return page
    .locator(".cm-line")
    .evaluateAll((lines) => lines.map((line) => line.textContent).join("\n"));
}
async function converge(a, b) {
  const end = Date.now() + 15000;
  while (Date.now() < end) {
    const left = await text(a);
    const right = await text(b);
    if (left === right) return left;
    await a.waitForTimeout(80);
  }
  throw new Error("Editors did not converge.");
}
async function insert(page, value) {
  const editor = page.locator(".cm-content");
  await editor.click();
  await page.keyboard.press("Control+End");
  await page.keyboard.insertText(value);
}
try {
  const a = await first.newPage({ viewport: { width: 1280, height: 900 } });
  const b = await second.newPage({ viewport: { width: 390, height: 844 } });
  for (const page of [a, b]) {
    await page.goto(process.env.UI_BASE_URL || "http://127.0.0.1:5173");
    await page.getByLabel("Workspace token").fill(token);
    await page.getByRole("button", { name: "Connect", exact: true }).click();
    await page
      .getByText("Connected and synchronized", { exact: true })
      .waitFor({ timeout: 30000 });
  }
  await converge(a, b);
  await Promise.all([insert(a, " Alpha"), insert(b, " Beta")]);
  let merged = await converge(a, b);
  assert.equal(merged.split("Alpha").length - 1, 1);
  assert.equal(merged.split("Beta").length - 1, 1);
  await a.locator(".cm-content").click();
  await a.keyboard.press("Control+Home");
  await a.keyboard.press("Delete");
  const deleted = await converge(a, b);
  assert.equal(deleted.length, merged.length - 1);
  await a.getByRole("button", { name: "Work offline", exact: true }).click();
  await a.getByText("Offline in this tab", { exact: true }).waitFor();
  await insert(a, " Offline");
  await insert(b, " Online");
  assert.notEqual(await text(a), await text(b));
  await b.locator(".cm-content").click();
  await b.keyboard.press("Control+Home");
  await b.keyboard.press("Delete");
  await a.getByRole("button", { name: "Reconnect", exact: true }).click();
  await a
    .getByText("Connected and synchronized", { exact: true })
    .waitFor({ timeout: 30000 });
  let final = await converge(a, b);
  for (const value of ["Alpha", "Beta", "Offline", "Online"])
    assert.equal(final.split(value).length - 1, 1, value);
  assert.equal(
    await a.evaluate(() => localStorage.length + sessionStorage.length),
    0,
  );
  assert(!a.url().includes(token));
  assert.equal(
    await b.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
    true,
  );
  if (process.env.REQUIRE_CLOUD === "1") {
    const { createPool } = await import("../dist-server/server/database.js");
    const Y = await import("yjs");
    const owner = createPool({
      ...process.env,
      PGUSER: process.env.OWNER_USER,
      PGPASSWORD: process.env.OWNER_PASSWORD,
    });
    const read = async () => {
      const row = (
        await owner.query(
          "SELECT state,revision,stored_at FROM notes.documents WHERE id='release-planning'",
        )
      ).rows[0];
      const doc = new Y.Doc();
      Y.applyUpdate(doc, row.state);
      const value = doc.getText("content").toString();
      doc.destroy();
      return { ...row, text: value };
    };
    const waitStored = async (expected) => {
      const end = Date.now() + 15000;
      while (Date.now() < end) {
        const row = await read();
        if (row.text === expected) return row;
        await a.waitForTimeout(100);
      }
      throw new Error("Cloud snapshot did not commit expected text.");
    };
    try {
      await waitStored(final);
      await a
        .getByText(/A snapshot was committed at/)
        .waitFor({ timeout: 15000 });
      const before = await read();
      const receipt = await a.locator(".persistence p").innerText();
      const blocker = await owner.connect();
      await blocker.query("BEGIN");
      await blocker.query(
        "SELECT id FROM notes.documents WHERE id='release-planning' FOR UPDATE",
      );
      try {
        await insert(a, " Delayed");
        final = await converge(a, b);
        await a.waitForTimeout(2300);
        assert.equal((await read()).text, before.text);
        assert.equal(await a.locator(".persistence p").innerText(), receipt);
        console.log(
          "Delayed store: peers synchronized while row lock held; database and last receipt remained previous committed snapshot.",
        );
      } finally {
        await blocker.query("COMMIT");
        blocker.release();
      }
      await waitStored(final);
      await a.waitForTimeout(300);
      const committed = await read();
      await owner.query(
        "CREATE FUNCTION notes.fail_browser_store() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic store failure'; END $$",
      );
      await owner.query(
        "CREATE TRIGGER fixture_browser_failure BEFORE UPDATE ON notes.documents FOR EACH ROW EXECUTE FUNCTION notes.fail_browser_store()",
      );
      try {
        await insert(b, " Failed");
        final = await converge(a, b);
        await a
          .getByText(/The last storage attempt failed/)
          .waitFor({ timeout: 15000 });
        assert.deepEqual((await read()).state, committed.state);
        assert.equal((await read()).revision, committed.revision);
        console.log(
          "Forced storage failure: shared edit visible, explicit failure displayed, prior Cloud binary/revision unchanged.",
        );
      } finally {
        await owner.query(
          "DROP TRIGGER fixture_browser_failure ON notes.documents",
        );
        await owner.query("DROP FUNCTION notes.fail_browser_store()");
      }
      await insert(a, " Recovered");
      final = await converge(a, b);
      const durable = await waitStored(final);
      await a
        .getByText(/A snapshot was committed at/)
        .waitFor({ timeout: 15000 });
      await b
        .getByText(/A snapshot was committed at/)
        .waitFor({ timeout: 15000 });
      await writeFile(
        path.join(evidence, "committed-state.json"),
        JSON.stringify(
          {
            document: "release-planning",
            text: final,
            stateHex: durable.state.toString("hex"),
            revision: durable.revision,
            storedAt: durable.stored_at.toISOString(),
          },
          null,
          2,
        ),
      );
      console.log(
        "Later edit triggers successful storage and recovers prior unsaved edit; commit-only receipt visible in both browsers.",
      );
    } finally {
      await owner.end();
    }
  }
  await a.screenshot({
    path: path.join(evidence, "desktop.png"),
    fullPage: true,
  });
  await b.screenshot({
    path: path.join(evidence, "mobile.png"),
    fullPage: true,
  });
  await writeFile(
    path.join(evidence, "browser-state.json"),
    JSON.stringify({ document: "release-planning", text: final }, null, 2),
  );
  console.log(
    "Two independent native Chromium processes converged after concurrent inserts, actual deletes, offline edits and reconnect; no duplicates, token storage or horizontal overflow. Synchronization is not claimed as database commit.",
  );
} finally {
  await first.close();
  await second.close();
}
