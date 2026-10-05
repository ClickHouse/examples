import { test, expect } from "@playwright/test";
test("two tabs receive CDC, join projects, filter locally, and rejected writes stay rejected", async ({
  page,
  context,
}) => {
  const second = await context.newPage();
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(e.message));
  second.on("pageerror", (e) => errors.push(e.message));
  await page.goto("/");
  await second.goto("/");
  await expect(
    page.getByText("Review the homepage copy", { exact: true }),
  ).toBeVisible({ timeout: 20000 });
  await expect(
    second.getByText("Review the homepage copy", { exact: true }),
  ).toBeVisible({ timeout: 20000 });
  await expect(
    page.getByText("Private laboratory task", { exact: true }),
  ).toHaveCount(0);
  for (const param of [
    "table=planning.projects",
    "where=true",
    "params[1]=private-lab",
    "columns=*",
  ]) {
    const r = await page.request.get(`/api/shapes/tasks?offset=-1&${param}`);
    expect(r.status()).toBe(400);
  }
  const reads: string[] = [];
  second.on("request", (r) => {
    if (r.method() === "GET" && r.url().includes("/api/"))
      reads.push(new URL(r.url()).pathname);
  });
  const rejectedTitle = "Rejected hidden project " + Date.now();
  const invalid = await page.request.post("/api/tasks", {
    headers: { Origin: await page.evaluate(() => location.origin) },
    data: {
      title: rejectedTitle,
      project_id: "10000000-0000-4000-8000-000000000099",
      priority: "high",
    },
  });
  expect(invalid.status()).toBe(400);
  const title = "Launch note " + Date.now();
  await page.getByLabel("Task title", { exact: true }).fill(title);
  await page
    .getByLabel("New task project")
    .selectOption("10000000-0000-4000-8000-000000000002");
  await page.getByRole("button", { name: "Add task" }).click();
  await expect(page.getByRole("status")).toHaveText("Saved and synchronized", {
    timeout: 25000,
  });
  const card = second
    .getByTestId("task")
    .filter({ has: second.getByRole("heading", { name: title, exact: true }) });
  await expect(card).toBeVisible();
  await expect(card.getByText("Launch", { exact: true })).toBeVisible();
  await expect(second.getByText(rejectedTitle, { exact: true })).toHaveCount(0);
  await page
    .getByLabel(`Status for ${title}`, { exact: true })
    .selectOption("doing");
  await expect(page.getByRole("status")).toHaveText("Saved and synchronized", {
    timeout: 25000,
  });
  await expect(
    second.getByLabel(`Status for ${title}`, { exact: true }),
  ).toHaveValue("doing");
  await second
    .getByLabel("Status filter", { exact: true })
    .selectOption("done");
  await expect(card).toHaveCount(0);
  await second
    .getByLabel("Status filter", { exact: true })
    .selectOption("doing");
  await expect(card).toBeVisible();
  await page.route("**/api/tasks", (route) =>
    route.fulfill({
      status: 400,
      contentType: "application/json",
      body: JSON.stringify({ error: "Deliberate rejected write" }),
    }),
  );
  await page
    .getByLabel("Task title", { exact: true })
    .fill("Must never appear");
  await page.getByRole("button", { name: "Add task" }).click();
  await expect(page.getByRole("status")).toHaveText(
    "Deliberate rejected write",
  );
  await expect(
    second.getByText("Must never appear", { exact: true }),
  ).toHaveCount(0);
  await page.unroute("**/api/tasks");
  expect(reads.every((path) => path.startsWith("/api/shapes/"))).toBe(true);
  expect(reads.length).toBeGreaterThan(0);
  expect(errors).toEqual([]);
  await second.getByLabel("Status filter", { exact: true }).selectOption("all");
  await second.screenshot({
    path: "docs/local-query-board.png",
    fullPage: true,
  });
});
