import { test, expect } from "@playwright/test";
import { execFileSync } from "node:child_process";
test("committed task survives interrupted stream and real engine restart", async ({
  page,
  context,
}) => {
  const container = process.env.ELECTRIC_TEST_CONTAINER;
  test.skip(
    !container,
    "Set ELECTRIC_TEST_CONTAINER to this example's owned engine container.",
  );
  if (
    !container ||
    !/^(pgts-board-electric-(native|managed)|fieldwork-electric)$/.test(
      container,
    )
  )
    throw new Error("Unexpected test container");
  const other = await context.newPage();
  await page.goto("/");
  await other.goto("/");
  await expect(
    page.getByText("Review the homepage copy", { exact: true }),
  ).toBeVisible({ timeout: 20000 });
  await expect(
    other.getByText("Review the homepage copy", { exact: true }),
  ).toBeVisible({ timeout: 20000 });
  execFileSync("docker", ["stop", container], { stdio: "ignore" });
  const title = "Stream recovery " + Date.now();
  try {
    await page.getByLabel("Task title", { exact: true }).fill(title);
    const committed = page.waitForResponse(
      (r) =>
        new URL(r.url()).pathname === "/api/tasks" &&
        r.request().method() === "POST",
    );
    await page.getByRole("button", { name: "Add task" }).click();
    const response = await committed;
    expect(response.status()).toBe(201);
    const result = await response.json();
    expect(result.task.title).toBe(title);
    await expect(page.getByLabel("Task title", { exact: true })).toHaveValue(
      "",
    );
    await expect(page.getByRole("status")).toContainText(
      "Saved to Postgres. The live stream is catching up",
      { timeout: 20000 },
    );
  } finally {
    execFileSync("docker", ["start", container], { stdio: "ignore" });
  }
  await expect(
    page.getByRole("heading", { name: title, exact: true }),
  ).toBeVisible({ timeout: 35000 });
  await expect(
    other.getByRole("heading", { name: title, exact: true }),
  ).toBeVisible({ timeout: 35000 });
  expect(
    await page.getByRole("heading", { name: title, exact: true }).count(),
  ).toBe(1);
});
