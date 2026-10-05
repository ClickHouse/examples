import { test, expect } from "@playwright/test";
test("browse nested variants, create, reorder, save and recover conflict", async ({
  page,
  context,
}) => {
  await page.goto("/");
  await expect(page.getByTestId("revision")).toHaveText(/^r\d+$/);
  await page.getByLabel("Category").selectOption("Travel");
  await expect(page.getByTestId("product").first()).toContainText("Travel");
  await page.getByLabel("Category").selectOption("");
  await page.getByLabel("Search products").fill("Canvas");
  await page.getByRole("button", { name: "Search", exact: true }).click();
  await expect(page.getByTestId("product")).toHaveCount(1);
  await page.getByText("3 variants · from").click();
  await expect(page.getByText("STUDIO-02-0")).toBeVisible();
  await page
    .getByRole("button", { name: "Add Canvas weekender", exact: true })
    .click();
  await page
    .getByLabel("Save this edit as a new collection")
    .fill("Weekend edit");
  await page
    .getByRole("button", { name: "Create collection", exact: true })
    .click();
  await expect(
    page.getByRole("heading", { name: "Weekend edit", exact: true }),
  ).toBeVisible();
  await expect(page.getByTestId("revision")).toHaveText("r1");
  const other = await context.newPage();
  const selected = new URL(page.url()).searchParams.get("collection")!;
  await other.goto("/?collection=" + selected);
  await expect(
    other.getByRole("heading", { name: "Weekend edit", exact: true }),
  ).toBeVisible();
  await expect(other.getByTestId("revision")).toHaveText("r1");
  await page.getByLabel("Move Canvas weekender up").click();
  await page
    .getByRole("button", { name: "Save collection", exact: true })
    .click();
  await expect(page.getByTestId("revision")).toHaveText("r2");
  await page.reload();
  await expect(page.locator(".selection li").nth(2)).toContainText(
    "Canvas weekender",
  );
  await other.getByLabel("Remove Arc desk lamp").click();
  await other
    .getByRole("button", { name: "Save collection", exact: true })
    .click();
  await expect(other.getByRole("status")).toContainText("another tab");
  other.once("dialog", (d) => d.accept());
  await other
    .getByRole("button", { name: "Reload saved collection", exact: true })
    .click();
  await expect(other.getByTestId("revision")).toHaveText("r2");
  await page.screenshot({
    path: "test-results/product-graphql.png",
    fullPage: true,
  });
  await other.close();
});
