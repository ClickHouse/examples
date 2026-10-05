import { chromium, expect } from "@playwright/test";
import { mkdir } from "node:fs/promises";
import { owner, start, stop, origin, client } from "./helpers";
const db = owner();
const id = 800000 + Math.floor(Math.random() * 90000);
const evidence =
  process.env.TEST_EVIDENCE_DIR ?? "/tmp/quote-catalogue-evidence";
await mkdir(evidence, { recursive: true });
let server: Awaited<ReturnType<typeof start>> | undefined;
const browser = await chromium.launch({ headless: true });
try {
  await db
    .insertInto("quotes")
    .values({
      id,
      title: "Studio session",
      days: 1,
      revision: 0,
      updated_at: new Date().toISOString(),
    })
    .execute();
  server = await start();
  const context = await browser.newContext({
    viewport: { width: 1440, height: 1100 },
  });
  const page = await context.newPage();
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.goto(origin + "/?quote=" + id);
  await expect(
    page.getByRole("button", { name: "Add Cinema camera", exact: true }),
  ).toBeEnabled();
  await page
    .getByRole("button", { name: "Add Cinema camera", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Increase Cinema camera", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Add LED panel", exact: true })
    .click();
  await page.getByLabel("Hire days").selectOption("3");
  await expect(page.getByTestId("total")).toHaveText("£444.00");
  await page.getByRole("button", { name: "Save quote", exact: true }).click();
  await expect(page.locator('[role="status"]')).toContainText("Quote saved");
  await page.reload();
  await expect(page.getByLabel("Quantity Cinema camera")).toHaveText("2");
  await expect(page.getByTestId("total")).toHaveText("£444.00");
  await page.screenshot({
    path: evidence + "/quote-saved.png",
    fullPage: true,
  });
  await page.getByLabel("Filter equipment").selectOption("Audio");
  await expect(page.locator("[data-product]")).toHaveCount(2);
  await page.getByLabel("Filter equipment").selectOption("All equipment");
  const other = await context.newPage();
  await other.goto(origin + "/?quote=" + id);
  await expect(other.getByLabel("Quantity Cinema camera")).toHaveText("2");
  await page
    .getByRole("button", { name: "Increase Cinema camera", exact: true })
    .click();
  await page.getByRole("button", { name: "Save quote", exact: true }).click();
  await expect(page.locator('[role="status"]')).toContainText("Quote saved");
  await other
    .getByRole("button", { name: "Increase LED panel", exact: true })
    .click();
  await other.getByRole("button", { name: "Save quote", exact: true }).click();
  await expect(other.locator('[role="status"]')).toContainText(
    "A newer quote was saved",
  );
  await expect(
    other.getByRole("button", { name: "Save quote", exact: true }),
  ).toBeDisabled();
  await other.screenshot({
    path: evidence + "/quote-conflict.png",
    fullPage: true,
  });
  await other
    .getByRole("button", { name: "Reload saved quote", exact: true })
    .click();
  await expect(other.getByRole("dialog")).toBeVisible();
  await other
    .getByRole("button", { name: "Discard and reload", exact: true })
    .click();
  await expect(other.getByLabel("Quantity Cinema camera")).toHaveText("3");
  await expect(other.getByTestId("total")).toHaveText("£639.00");
  await page
    .getByRole("link", { name: "Read the equipment-hire guide" })
    .click();
  await expect(
    page.getByRole("heading", { name: "Start with the shot" }),
  ).toBeVisible();
  await page.screenshot({ path: evidence + "/hire-guide.png", fullPage: true });
  expect((await client.get({ id })).totalMinor).toBe(63900);
  expect(errors).toEqual([]);
  const failing = await context.newPage();
  await failing.route("**/rpc/get", (r) =>
    r.fulfill({ status: 503, body: "{}" }),
  );
  await failing.goto(origin + "/?quote=" + id);
  await expect(failing.locator('[role="status"]')).toContainText(
    "The quote could not be loaded",
  );
  console.log(
    "PASS real hydrated Preact/daisyUI catalogue, quantities/days, typed oRPC save/reload, integer saved total and category filter",
  );
  console.log(
    "PASS two-tab conflict, discard modal/reload, Astro hire guide, visible RPC failure; no browser errors",
  );
} finally {
  await browser.close();
  await stop(server);
  await db.deleteFrom("quotes").where("id", "=", id).execute();
  await db.destroy();
}
