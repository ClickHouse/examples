import assert from "node:assert/strict";
import { chromium } from "@playwright/test";
import { spawn } from "node:child_process";
import { mkdir } from "node:fs/promises";
import pg from "pg";
import { connection } from "../server/db.js";
const origin = process.env.APP_ORIGIN ?? "http://127.0.0.1:4331";
const evidence = process.env.EVIDENCE_DIR ?? "/home/al/appointment-evidence";
await mkdir(evidence, { recursive: true });
const server = spawn(process.execPath, ["build/server/server.js"], {
  env: process.env,
  stdio: ["ignore", "pipe", "pipe"],
});
await new Promise<void>((resolve, reject) => {
  server.stdout!.once("data", () => resolve());
  server.once("exit", (code) => reject(new Error("server " + code)));
});
const browser = await chromium.launch({ headless: true });
try {
  const page = await browser.newPage({
    viewport: { width: 1360, height: 1120 },
    timezoneId: "UTC",
  });
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.goto(origin + "/calendar");
  await page.getByText("Morgan", { exact: false }).first().waitFor();
  await page.screenshot({ path: evidence + "/calendar.png", fullPage: true });
  // A deliberately delayed previous-day response must not replace the later selection.
  await page.route("**/api/day?date=2026-10-06", async (route) => {
    const response = await route.fetch();
    await new Promise((r) => setTimeout(r, 900));
    await route.fulfill({ response });
  });
  await page.locator("#day").fill("2026-10-06");
  await page.locator("#day").dispatchEvent("change");
  await page.locator("#day").fill("2026-10-05");
  await page.locator("#day").dispatchEvent("change");
  await page.getByText("Morgan", { exact: false }).first().waitFor();
  await page.waitForTimeout(1200);
  assert.equal(
    (await page.getByText("Morgan", { exact: false }).count()) > 0,
    true,
  );
  console.log("Delayed earlier-day response cannot overwrite current day");
  async function dragMorgan(from: string, to: string) {
    const event = page.getByText("Morgan", { exact: false }).first();
    const box = await event.boundingBox();
    assert.ok(box);
    const laneY = async (time: string) =>
      page
        .locator(`[data-time="${time}"]`)
        .evaluateAll(
          (es) =>
            es
              .find((e) => e.getBoundingClientRect().width > 100)!
              .getBoundingClientRect().y,
        );
    const delta = (await laneY(to)) - (await laneY(from));
    const response = page.waitForResponse(
      (r) =>
        r.url().endsWith("/api/appointments/1") &&
        r.request().method() === "PUT",
    );
    await page.mouse.move(box.x + 70, box.y + 8);
    await page.mouse.down();
    await page.mouse.move(box.x + 70, box.y + 8 + delta, { steps: 25 });
    await page.mouse.up();
    return response;
  }
  assert.equal((await dragMorgan("09:00:00", "11:00:00")).status(), 200);
  await page
    .getByRole("status")
    .filter({ hasText: "Appointment saved." })
    .waitFor();
  await page.reload();
  await page.getByText("Morgan", { exact: false }).first().waitFor();
  let savedDay = await (
    await page.request.get(origin + "/api/day?date=2026-10-05")
  ).json();
  assert.equal(
    savedDay.appointments.find((a: { id: number }) => a.id === 1).startsAt,
    "2026-10-05T10:00:00.000Z",
  );
  assert.equal((await dragMorgan("11:00:00", "10:00:00")).status(), 409);
  await page
    .getByRole("alert")
    .filter({ hasText: "already has an appointment" })
    .waitFor();
  await page.getByText("Morgan", { exact: false }).first().waitFor();
  assert.match(
    await page
      .getByText("Morgan", { exact: false })
      .first()
      .evaluate((e) => e.parentElement!.textContent ?? ""),
    /11:00/,
  );
  savedDay = await (
    await page.request.get(origin + "/api/day?date=2026-10-05")
  ).json();
  assert.equal(
    savedDay.appointments.find((a: { id: number }) => a.id === 1).startsAt,
    "2026-10-05T10:00:00.000Z",
  );
  await page.screenshot({
    path: evidence + "/overlap-restored.png",
    fullPage: true,
  });
  console.log(
    "Native FullCalendar successful drag persists; occupied drop receives409 and restores displayed committed11:00",
  );
  await page.getByText("Morgan", { exact: false }).first().click();
  await page.locator("#customer").fill("");
  await page
    .getByRole("button", { name: "Save appointment", exact: true })
    .click();
  await page.getByText("Enter at least two characters.").waitFor();
  await page.locator("#customer").fill("Morgan Reed");
  await page.locator("#service").click();
  await page
    .getByRole("option", { name: "Routine service", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Save appointment", exact: true })
    .click();
  await page
    .getByRole("status")
    .filter({ hasText: "Appointment saved." })
    .waitFor();
  await page.getByRole("link", { name: "Utilization", exact: true }).click();
  await page.getByText("360 minutes", { exact: true }).waitFor();
  await page.screenshot({
    path: evidence + "/utilization.png",
    fullPage: true,
  });
  assert.deepEqual(errors, []);
  console.log(
    "PrimeVue modal, VeeValidate input, Vue Router chart and stored totals passed without page errors",
  );
} finally {
  const owner = new pg.Pool({
    ...connection(),
    user: process.env.DB_OWNER_USER,
    password: process.env.DB_OWNER_PASSWORD,
  });
  await owner.query(
    "UPDATE appointments SET starts_at='2026-10-05T08:00:00Z',ends_at='2026-10-05T08:30:00Z',service_id=1,duration_minutes=30,customer='Morgan Reed',revision=revision+1 WHERE id=1",
  );
  await owner.end();
  await browser.close();
  await new Promise<void>((resolve) => {
    server.once("exit", () => resolve());
    server.kill("SIGTERM");
  });
}
