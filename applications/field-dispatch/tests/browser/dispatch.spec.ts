import { test, expect } from "@playwright/test";
import { spawn, type ChildProcess } from "node:child_process";
import { once } from "node:events";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { database, closeDatabase } from "../../server/database";
import { bootstrap, saveMap } from "../../server/dispatch";
const base = process.env.APP_ORIGIN ?? "http://127.0.0.1:3002";
const evidence = process.env.EVIDENCE_DIR ?? "test-results";
let server: ChildProcess;
async function startServer() {
  server = spawn(
    process.execPath,
    ["--env-file=.env", "--import", "tsx", "server/index.ts"],
    { stdio: "ignore", env: process.env },
  );
  for (let i = 0; i < 80; i++) {
    if (server.exitCode !== null) throw new Error("Dispatch server exited.");
    try {
      if ((await fetch(base)).ok) return;
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error("Dispatch server did not start.");
}
async function stopServer() {
  if (server && server.exitCode === null) {
    const exited = once(server, "exit");
    server.kill("SIGTERM");
    await exited;
  }
}
test.beforeAll(async () => {
  mkdirSync(evidence, { recursive: true });
  // Dedicated demo test fixture only: restore two jobs and the singleton view.
  await database().query(
    "UPDATE dispatch.jobs SET team_id=NULL,revision=revision+1 WHERE code IN ('FD-001','FD-002')",
  );
  const state = (await bootstrap()).state;
  await saveMap({
    ...state,
    longitude: -1.467,
    latitude: 53.373,
    zoom: 13,
    areaId: "20000000-0000-4000-8000-000000000001",
    mode: "assignments",
  });
  await startServer();
});
test.afterAll(async () => {
  await stopServer();
  await closeDatabase();
});
test("actual WebGL, PMTiles, deck picking, coverage, assignment, viewport retry and saved-view process restart", async ({
  page,
  request,
}) => {
  let viewportRequest = "";
  page.on("request", (req) => {
    if (req.url().includes("/api/jobs?")) viewportRequest = req.url();
  });

  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  const ranges: { status: number; range: string | null }[] = [];
  page.on("response", (response) => {
    if (response.url().endsWith(".pmtiles"))
      ranges.push({
        status: response.status(),
        range: response.headers()["content-range"] ?? null,
      });
  });
  await page.goto("/");
  await expect(
    page.getByText("Map ready · Synthetic town", { exact: true }),
  ).toBeVisible();
  await expect(page.getByRole("button", { name: /FD-001/ })).toBeVisible();
  await expect
    .poll(() => ranges.filter((value) => value.status === 206).length)
    .toBeGreaterThan(0);
  const canvas = page.locator("canvas.maplibregl-canvas");
  const rendered = await canvas.evaluate((element: HTMLCanvasElement) => {
    const gl = element.getContext("webgl2")!;
    if (!gl) throw new Error("No actual WebGL2 context.");
    const pixels = new Uint8Array(
      gl.drawingBufferWidth * gl.drawingBufferHeight * 4,
    );
    gl.readPixels(
      0,
      0,
      gl.drawingBufferWidth,
      gl.drawingBufferHeight,
      gl.RGBA,
      gl.UNSIGNED_BYTE,
      pixels,
    );
    const colors = new Set<string>();
    for (let i = 0; i < pixels.length; i += 400)
      colors.add(
        `${pixels[i]},${pixels[i + 1]},${pixels[i + 2]},${pixels[i + 3]}`,
      );
    return {
      webgl: gl.getParameter(gl.VERSION),
      renderer: gl.getParameter(gl.RENDERER),
      colors: colors.size,
    };
  });
  expect(rendered.colors).toBeGreaterThan(5);
  const state = (await (await request.get("/api/bootstrap")).json()).state;
  const size = await canvas.boundingBox();
  expect(size).not.toBeNull();
  const query = new URL(viewportRequest).searchParams;
  const bounds = Object.fromEntries(
    [...query].map(([key, value]) => [key, Number(value)]),
  );
  const projected = await page.evaluate(
    ({ bounds, width, height }) => {
      const mercator = (lat: number) =>
        Math.log(Math.tan(Math.PI / 4 + (lat * Math.PI) / 360));
      return {
        x: ((-1.481 - bounds.west) / (bounds.east - bounds.west)) * width,
        y:
          ((mercator(bounds.north) - mercator(53.361)) /
            (mercator(bounds.north) - mercator(bounds.south))) *
          height,
      };
    },
    { bounds, width: size!.width, height: size!.height },
  );
  writeFileSync(
    join(evidence, "picking-debug.json"),
    JSON.stringify({ state, size, projected, rendered }),
  );
  await page.screenshot({
    path: join(evidence, "picking-debug.png"),
    fullPage: true,
  });
  await page.waitForTimeout(1000);
  await page.mouse.click(size!.x + projected.x, size!.y + projected.y);
  await expect(page.locator(".review-panel h2")).toContainText("FD-001");
  await expect(page.locator(".review-panel")).toContainText(
    "Inside West garden",
  );
  await page
    .getByRole("button", { name: "Assign Garden crew", exact: true })
    .click();
  await expect(page.getByRole("status")).toContainText(
    "Garden crew assigned to FD-001",
  );
  await expect(page.getByRole("button", { name: /FD-001/ })).toContainText(
    "Garden crew",
  );
  const jobs = (
    await (
      await request.get(
        "/api/jobs?west=-1.51&south=53.33&east=-1.41&north=53.41",
      )
    ).json()
  ).jobs;
  expect(
    (
      await request.post("/api/map", {
        headers: { origin: "https://wrong-origin.invalid" },
        data: state,
      })
    ).status(),
  ).toBe(403);
  const first = jobs.find((job: any) => job.code === "FD-001");
  const stale = await request.post("/api/assign", {
    headers: { origin: base },
    data: {
      jobId: first.id,
      teamId: first.teamId,
      revision: first.revision - 1,
    },
  });
  expect(stale.status()).toBe(409);
  await page.getByRole("button", { name: /FD-002/ }).click();
  await expect(page.locator(".review-panel")).toContainText(
    "Outside West garden",
  );
  await expect(
    page.getByRole("button", { name: "Assign Garden crew", exact: true }),
  ).toBeDisabled();
  const river = jobs.find((job: any) => job.code === "FD-002");
  expect(
    (
      await request.post("/api/assign", {
        headers: { origin: base },
        data: {
          jobId: river.id,
          teamId: first.teamId,
          revision: river.revision,
        },
      })
    ).status(),
  ).toBe(400);
  await page
    .getByRole("combobox", { name: "Service area", exact: true })
    .selectOption("20000000-0000-4000-8000-000000000002");
  await expect(page.locator(".review-panel")).toContainText("Inside Riverside");
  await page
    .getByRole("button", { name: "Assign River crew", exact: true })
    .click();
  await expect(page.getByRole("status")).toContainText(
    "River crew assigned to FD-002",
  );
  await page
    .getByRole("combobox", { name: "Map layer", exact: true })
    .selectOption("priority");
  await page.route("**/api/jobs?**", (route) =>
    route.fulfill({
      status: 503,
      contentType: "application/json",
      body: JSON.stringify({ error: "Controlled viewport failure" }),
    }),
  );
  await page.getByRole("button", { name: "Refresh jobs" }).click();
  await expect(
    page.getByRole("heading", { name: "Jobs unavailable" }),
  ).toBeVisible();
  await expect(page.locator(".jobs button")).toHaveCount(0);
  await page.unroute("**/api/jobs?**");
  await page.getByRole("button", { name: "Refresh jobs" }).click();
  await expect(page.getByRole("button", { name: /FD-001/ })).toBeVisible();
  await expect(page.getByRole("alert")).toHaveCount(0);
  const before = (await (await request.get("/api/bootstrap")).json()).state;
  await page.mouse.move(size!.x + size!.width / 2, size!.y + size!.height / 2);
  await page.mouse.down();
  await page.mouse.move(
    size!.x + size!.width / 2 + 90,
    size!.y + size!.height / 2 + 35,
    { steps: 12 },
  );
  await page.mouse.up();
  await page.waitForTimeout(700);
  await page.getByRole("button", { name: "Save map view" }).click();
  await expect(page.getByRole("status")).toContainText("Map view saved");
  const saved = (await (await request.get("/api/bootstrap")).json()).state;
  expect(saved.longitude).not.toBe(before.longitude);
  expect(saved.mode).toBe("priority");
  expect(saved.areaId).toBe("20000000-0000-4000-8000-000000000002");
  await page.screenshot({
    path: join(evidence, "dispatch-desktop.png"),
    fullPage: true,
  });
  const originalPid = server.pid;
  await stopServer();
  await startServer();
  await page.reload();
  await expect(
    page.getByText("Map ready · Synthetic town", { exact: true }),
  ).toBeVisible();
  await expect(
    page.getByRole("combobox", { name: "Map layer", exact: true }),
  ).toHaveValue("priority");
  expect((await (await request.get("/api/bootstrap")).json()).state).toEqual(
    saved,
  );
  const restored = (
    await (
      await request.get(
        "/api/jobs?west=-1.51&south=53.33&east=-1.41&north=53.41",
      )
    ).json()
  ).jobs;
  expect(restored.find((job: any) => job.code === "FD-001").teamId).toBe(
    first.teamId,
  );
  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForTimeout(500);
  await page.screenshot({
    path: join(evidence, "dispatch-mobile.png"),
    fullPage: true,
  });
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
  ).toBe(true);
  expect(errors).toEqual([]);
  writeFileSync(
    join(evidence, "restart.json"),
    JSON.stringify(
      {
        originalPid,
        replacementPid: server.pid,
        saved,
        assignmentsRestored: true,
      },
      null,
      2,
    ),
  );
  writeFileSync(
    join(evidence, "webgl.json"),
    JSON.stringify(
      {
        rendered,
        ranges,
        picking: "FD-001 actual deck point",
        viewportFailureCleared: true,
      },
      null,
      2,
    ),
  );
});
