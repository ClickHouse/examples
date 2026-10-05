import assert from "node:assert/strict";
import { chromium } from "@playwright/test";
import { spawn } from "node:child_process";
import { mkdir } from "node:fs/promises";
const evidence = process.env.EVIDENCE_DIR ?? "test-artifacts";
await mkdir(evidence, { recursive: true });
const origin = "http://127.0.0.1:4331";
const server = spawn(process.execPath, ["build/server/server.js"], {
  env: { ...process.env, APP_ORIGIN: origin },
  stdio: ["ignore", "pipe", "pipe"],
});
await new Promise<void>((resolve, reject) => {
  server.stdout!.once("data", () => resolve());
  server.once("exit", (code) => reject(new Error("server " + code)));
});
const browser = await chromium.launch();
try {
  const page = await browser.newPage();
  // UI-only control: response fixtures isolate loading/failure state after managed cleanup.
  await page.route("**/api/day?**", async (route) => {
    const date = new URL(route.request().url()).searchParams.get("date")!;
    if (date === "2026-10-06") {
      await new Promise((r) => setTimeout(r, 700));
      await route.fulfill({
        status: 500,
        json: { message: "Controlled unavailable day" },
      });
      return;
    }
    await route.fulfill({
      status: 200,
      json: {
        date,
        zone: "Europe/London",
        bays: [{ id: 1, name: "Inspection bay" }],
        services: [],
        appointments: [],
        utilization: [{ bayId: 1, name: "Inspection bay", bookedMinutes: 120 }],
      },
    });
  });
  await page.goto(origin + "/utilization");
  await page.getByText("120 minutes", { exact: true }).waitFor();
  await page.locator("canvas").waitFor({ state: "visible" });
  await page.locator("#day").fill("2026-10-06");
  await page.locator("#day").dispatchEvent("change");
  await page.getByText("Loading utilization…", { exact: true }).waitFor();
  assert.equal(await page.locator("canvas").isVisible(), false);
  assert.equal(await page.locator("table").count(), 0);
  assert.equal(await page.getByText("120 minutes", { exact: true }).count(), 0);
  await page
    .getByText("Utilization unavailable. Reload the selected day.", {
      exact: true,
    })
    .waitFor();
  assert.equal(await page.locator("canvas").isVisible(), false);
  assert.equal(await page.locator("table").count(), 0);
  await page.locator("#day").fill("2026-10-05");
  await page.locator("#day").dispatchEvent("change");
  await page.getByText("120 minutes", { exact: true }).waitFor();
  await page.locator("canvas").waitFor({ state: "visible" });
  await page.waitForFunction(() => {
    const canvas = document.querySelector("canvas")!;
    const pixels = canvas
      .getContext("2d")!
      .getImageData(0, 0, canvas.width, canvas.height).data;
    let green = 0;
    for (let i = 0; i < pixels.length; i += 4)
      if (
        pixels[i] === 36 &&
        pixels[i + 1] === 123 &&
        pixels[i + 2] === 104 &&
        pixels[i + 3] > 240
      )
        green++;
    return green > 5000;
  });
  await page.screenshot({
    path: evidence + "/utilization-ui-final.png",
    fullPage: true,
  });
  console.log(
    "Final Chart.js bars painted with animation disabled (pixel control), UI-only fixture120minutes",
  );
  console.log(
    "UI-only delayed/failing new-day response hides old chart/table/totals; subsequent success redraws chart",
  );
} finally {
  await browser.close();
  await new Promise<void>((resolve) => {
    server.once("exit", () => resolve());
    server.kill("SIGTERM");
  });
}
