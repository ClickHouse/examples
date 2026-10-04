import { expect, test } from "@playwright/test";
test("edit, connect, layout, save, reload and stale tab conflict", async ({
  page,
  context,
}) => {
  const other = await context.newPage();
  await page.goto("/");
  await other.goto("/");
  await expect(page.getByTestId("revision")).not.toHaveText("—");
  const originalRevision = Number(
    await page.getByTestId("revision").innerText(),
  );
  await page.getByRole("button", { name: "+ Add service" }).click();
  await page.getByTestId("service-card").filter({ hasText: "New api" }).click();
  await page
    .getByRole("textbox", { name: "Service name" })
    .fill("Inventory API");
  const node = page
    .locator(".react-flow__node")
    .filter({ hasText: "Inventory API" });
  const prior = await node.boundingBox();
  if (!prior) throw new Error("Node not rendered");
  await page.mouse.move(prior.x + 100, prior.y + 55);
  await page.mouse.down();
  await page.mouse.move(prior.x + 160, prior.y + 105, { steps: 8 });
  await page.mouse.up();
  await expect(page.getByTestId("save-state")).toHaveText("Unsaved changes");
  // React Flow's actual source/target handles create an edge.
  const edgeCount = await page.locator(".react-flow__edge").count();
  const source = await page
    .locator(".react-flow__node")
    .filter({ hasText: "Inventory API" })
    .locator(".react-flow__handle.source")
    .boundingBox();
  const target = await page
    .locator(".react-flow__node")
    .filter({ hasText: "Checkout API" })
    .locator(".react-flow__handle.target")
    .boundingBox();
  if (!source || !target) throw new Error("Handles not rendered");
  await page.mouse.move(
    source.x + source.width / 2,
    source.y + source.height / 2,
  );
  await page.mouse.down();
  await page.mouse.move(
    target.x + target.width / 2,
    target.y + target.height / 2,
    { steps: 12 },
  );
  await page.mouse.up();
  await expect(page.locator(".react-flow__edge")).toHaveCount(edgeCount + 1);
  await page.getByRole("button", { name: "Auto layout" }).click();
  await expect(
    page.getByRole("button", { name: "Save revision" }),
  ).toBeEnabled();
  await page.getByRole("button", { name: "Save revision" }).click();
  await expect(page.getByTestId("revision")).toHaveText(
    String(originalRevision + 1).padStart(2, "0"),
  );
  await page.reload();
  await expect(
    page.getByTestId("service-card").filter({ hasText: "Inventory API" }),
  ).toBeVisible();
  await other.getByRole("button", { name: "+ Add service" }).click();
  await other.getByRole("button", { name: "Save revision" }).click();
  await expect(other.getByTestId("save-state")).toHaveText("Save conflict");
  other.once("dialog", (dialog) => dialog.accept());
  await other.getByRole("button", { name: "Reload saved revision" }).click();
  await expect(other.getByTestId("revision")).toHaveText(
    String(originalRevision + 1).padStart(2, "0"),
  );
  await page.locator(".react-flow__pane").click({ position: { x: 20, y: 20 } });
  await page.screenshot({
    path: process.env.SCREENSHOT_PATH || "test-results/topology.png",
    fullPage: true,
  });
  await other.close();
  await page
    .getByTestId("service-card")
    .filter({ hasText: "Inventory API" })
    .click();
  await page.getByRole("button", { name: "Remove service" }).click();
  await page.getByRole("button", { name: "Save revision" }).click();
  await expect(page.getByTestId("revision")).toHaveText(
    String(originalRevision + 2).padStart(2, "0"),
  );
  await page.reload();
  await expect(
    page.getByTestId("service-card").filter({ hasText: "Inventory API" }),
  ).toHaveCount(0);
});
