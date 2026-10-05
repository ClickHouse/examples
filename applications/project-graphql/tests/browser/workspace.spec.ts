import { test, expect } from "@playwright/test";
test("real Apollo pages, generated writes and cache replacement across verified sessions", async ({
  page,
}) => {
  await page.goto("/");
  await page.getByLabel("Password", { exact: true }).fill("river-demo");
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(
    page.getByRole("heading", { name: "Riverside Studio" }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Pagination notebook" }).click();
  await expect(
    page.getByText("50 of 51 tasks", { exact: false }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Load more tasks" }).click();
  await expect(
    page.getByText("51 of 51 tasks", { exact: false }),
  ).toBeVisible();
  await expect(
    page.getByText("Pagination step 51", { exact: true }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Load more projects" }).click();
  await expect(
    page.getByRole("button", { name: "Load more projects" }),
  ).toHaveCount(0);
  const name = "Launch notebook " + Date.now();
  await page.getByLabel("New project name").fill(name);
  await page
    .getByLabel("New project description")
    .fill("A small launch checklist for the team");
  await page.getByRole("button", { name: "Create project" }).click();
  await expect(page.getByRole("heading", { name })).toBeVisible();
  await expect(page.getByRole("button", { name, exact: false })).toBeVisible();
  await page.getByLabel("New task title").fill("Review the launch notes");
  await page.getByRole("button", { name: "Add task" }).click();
  await expect(
    page.getByText("Review the launch notes", { exact: true }),
  ).toBeVisible();
  await page
    .getByRole("checkbox", { name: "Complete Review the launch notes" })
    .click();
  await expect(
    page.getByRole("checkbox", { name: "Complete Review the launch notes" }),
  ).toBeChecked();
  await page.screenshot({
    path: ".deployment/workspace-browser.png",
    fullPage: true,
  });
  await page.getByRole("button", { name: "Switch workspace" }).click();
  await page
    .getByLabel("Account", { exact: true })
    .selectOption("bob@example.test");
  await page.getByLabel("Password", { exact: true }).fill("summit-demo");
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(
    page.getByRole("heading", { name: "Summit Team" }),
  ).toBeVisible();
  await expect(page.getByText(name, { exact: true })).toHaveCount(0);
  await expect(
    page.getByText("Review the launch notes", { exact: true }),
  ).toHaveCount(0);
  await expect(
    page.getByRole("button", { name: "Pagination notebook" }),
  ).toHaveCount(0);
  await page.getByRole("button", { name: "Switch workspace" }).click();
  await page.getByLabel("Password", { exact: true }).fill("river-demo");
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.getByRole("button", { name, exact: false }).click();
  await expect(
    page.getByRole("checkbox", { name: "Complete Review the launch notes" }),
  ).toBeChecked();
});

test("a late session response cannot restore an old workspace; transport failures are visible", async ({
  page,
  context,
}) => {
  const origin = process.env.APP_ORIGIN ?? "http://127.0.0.1:3002";
  async function account(email: string, password: string) {
    const response = await context.request.post(origin + "/api/login", {
      headers: { Origin: origin },
      data: { email, password },
    });
    expect(response.status()).toBe(200);
  }
  await account("alice@example.test", "river-demo");
  let release!: () => void;
  let captured!: () => void;
  const gate = new Promise<void>((resolve) => (release = resolve));
  const ready = new Promise<void>((resolve) => (captured = resolve));
  let first = true;
  await page.route("**/api/me", async (route) => {
    if (!first) {
      await route.continue();
      return;
    }
    first = false;
    const response = await route.fetch();
    const body = await response.body();
    captured();
    await gate;
    await route.fulfill({ response, body });
  });
  await page.goto("/");
  await ready;
  await account("bob@example.test", "summit-demo");
  const broadcaster = await context.newPage();
  await broadcaster.goto("/");
  await broadcaster.evaluate(() => {
    const c = new BroadcastChannel("common-ground-session");
    c.postMessage("changed");
    c.close();
  });
  await expect(
    page.getByRole("heading", { name: "Summit Team" }),
  ).toBeVisible();
  release();
  await expect(
    page.getByRole("heading", { name: "Riverside Studio" }),
  ).toHaveCount(0);
  await expect(
    page.getByRole("heading", { name: "Summit Team" }),
  ).toBeVisible();
  await page.route("**/api/logout", (route) => route.abort());
  await page.getByRole("button", { name: "Switch workspace" }).click();
  await expect(page.getByRole("alert")).toContainText("Could not sign out");
  await expect(
    page.getByRole("heading", { name: "Summit Team" }),
  ).toBeVisible();
  await page.unroute("**/api/logout");
  await page.getByRole("button", { name: "Switch workspace" }).click();
  await page.route("**/api/login", (route) => route.abort());
  await page.getByLabel("Password", { exact: true }).fill("river-demo");
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page.getByRole("alert")).toContainText("Could not sign in");
});
