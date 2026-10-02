import { chromium, expect as baseExpect } from "@playwright/test";
import { mkdir } from "node:fs/promises";
import assert from "node:assert/strict";
const base = process.env.BASE_URL || "http://127.0.0.1:3000";
const output = process.env.EVIDENCE_DIR || "/tmp/team-directory-evidence";
await mkdir(output, { recursive: true });
const expect = baseExpect.configure({ timeout: 30000 });
const browser = await chromium.launch({ headless: true });
const contexts = [];
const errors = [];
async function account(email) {
  const context = await browser.newContext({
    viewport: { width: 1360, height: 950 },
  });
  contexts.push(context);
  await context.tracing.start({ screenshots: true, snapshots: true });
  const page = await context.newPage();
  page.on("pageerror", (e) => errors.push(e.message));
  await page.goto(base + "/login");
  await page.getByLabel("Email", { exact: true }).fill(email);
  await page
    .getByLabel("Password", { exact: true })
    .fill(process.env.DEMO_PASSWORD);
  await page.getByRole("button", { name: "Sign in", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "People directory" }),
  ).toBeVisible();
  return { context, page };
}
try {
  const alex = await account("alex@example.test");
  const sam = await account("sam@example.test");
  await alex.page
    .getByRole("link", { name: "My profile", exact: true })
    .click();
  await expect(alex.page.getByLabel("Display name")).toBeVisible();
  await alex.page.getByLabel("Display name").fill("Alex Directory");
  await alex.page
    .getByLabel("Biography")
    .fill("Builds thoughtful tools with TypeScript and Postgres.");
  await alex.page.getByLabel("Location", { exact: true }).fill("London");
  await alex.page.getByLabel("Design", { exact: true }).uncheck();
  await alex.page.getByLabel("Postgres", { exact: true }).check();
  await alex.page.getByLabel("TypeScript", { exact: true }).check();
  await alex.page
    .getByRole("button", { name: "Save profile", exact: true })
    .click();
  await expect(alex.page.getByRole("status")).toHaveText("Profile saved.");
  await alex.page.reload();
  await expect(alex.page.getByLabel("Display name")).toHaveValue(
    "Alex Directory",
  );
  await expect(
    alex.page.getByLabel("TypeScript", { exact: true }),
  ).toBeChecked();
  await alex.page.screenshot({
    path: output + "/directory-profile.png",
    fullPage: true,
  });
  await sam.page.getByLabel("Search", { exact: true }).fill("Alex Directory");
  await sam.page.getByLabel("Skill", { exact: true }).selectOption("3");
  await sam.page.getByRole("button", { name: "Find people" }).click();
  await expect(
    sam.page.getByRole("heading", { name: "Alex Directory", exact: true }),
  ).toBeVisible();
  await expect(sam.page.locator(".person-card")).toHaveCount(1);
  assert.equal(
    await sam.page
      .locator(".person-card")
      .getByText("TypeScript", { exact: true })
      .count(),
    1,
  );
  const forbidden = await sam.page.request.put(
    base + "/api/profiles/00000000-0000-4000-8000-000000000001",
    {
      headers: { Origin: new URL(base).origin },
      data: {
        revision: 1,
        displayName: "Forged",
        biography: "",
        location: "",
        skillIds: [],
      },
    },
  );
  assert.equal(forbidden.status(), 404);
  const stale = await alex.context.newPage();
  stale.on("pageerror", (e) => errors.push(e.message));
  await stale.goto(base + "/profile");
  await expect(stale.getByLabel("Display name")).toHaveValue("Alex Directory");
  await alex.page
    .getByLabel("Biography")
    .fill("Updated in the first browser tab.");
  await alex.page
    .getByRole("button", { name: "Save profile", exact: true })
    .click();
  await expect(alex.page.getByRole("status")).toHaveText("Profile saved.");
  await stale
    .getByLabel("Biography")
    .fill("Stale browser must not overwrite this.");
  await stale
    .getByRole("button", { name: "Save profile", exact: true })
    .click();
  await expect(stale.getByRole("status")).toContainText("This profile changed");
  await stale.getByRole("button", { name: "Reload latest" }).click();
  await expect(stale.getByLabel("Biography")).toHaveValue(
    "Updated in the first browser tab.",
  );
  await alex.page.getByRole("link", { name: "Directory", exact: true }).click();
  await expect(
    alex.page.getByRole("heading", { name: "People directory" }),
  ).toBeVisible();
  const response = await alex.page.reload();
  assert.ok(
    (await response.text()).includes("Alex Directory"),
    "Authenticated directory is rendered server-side",
  );
  await expect(alex.page.locator(".person-card")).toHaveCount(12);
  await alex.page.screenshot({
    path: output + "/directory-desktop.png",
    fullPage: true,
  });
  await alex.page.getByRole("button", { name: "Next →", exact: true }).click();
  await expect(alex.page.locator(".person-card")).toHaveCount(4);
  await alex.page.setViewportSize({ width: 390, height: 844 });
  await alex.page.goto(base + "/profile");
  await expect(alex.page.getByLabel("Display name")).toBeVisible();
  assert.ok(
    await alex.page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
  );
  await alex.page.screenshot({
    path: output + "/directory-mobile.png",
    fullPage: true,
  });
  await sam.page.getByRole("button", { name: "Sign out" }).click();
  await expect(
    sam.page.getByRole("heading", { name: "Sign in", exact: true }),
  ).toBeVisible();
  assert.equal(
    (await sam.page.request.get(base + "/api/directory")).status(),
    401,
  );
  assert.deepEqual(errors, []);
  console.log(
    "Browser passed: two accounts, actual profile+skills save, filter, refresh, foreign write denial, stale editor rejection, SSR, paging, mobile fit, native logout.",
  );
} catch (error) {
  for (let i = 0; i < contexts.length; i++)
    await contexts[i].tracing.stop({ path: output + `/failure-${i}.zip` });
  throw error;
} finally {
  await browser.close();
}
