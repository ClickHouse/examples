import { expect, type Locator, type Page } from "@playwright/test";
import { editorContent, editorFrame } from "./layout";

async function visibleControl(page: Page, control: Locator) {
  const box = (await control.boundingBox())!;
  expect(box.x).toBeGreaterThanOrEqual(0);
  expect(box.y).toBeGreaterThanOrEqual(0);
  expect(box.x + box.width).toBeLessThanOrEqual(page.viewportSize()!.width);
  expect(box.y + box.height).toBeLessThanOrEqual(page.viewportSize()!.height);
  if (await control.isEnabled()) {
    expect(await control.evaluate((element) => {
      const bounds = element.getBoundingClientRect();
      return element.contains(document.elementFromPoint(bounds.x + bounds.width / 2, bounds.y + bounds.height / 2));
    })).toBe(true);
  }
}

/** An open creator. Leaves newsletter parameters applied to its draft, UTMs closed. */
export async function verifyUtmTransactions(page: Page, size: "desktop" | "mobile", createTemplate = false) {
  page.setDefaultTimeout(15_000);
  const popup = page.getByRole("dialog", { name: "UTM parameters", exact: true });
  const menu = page.getByRole("dialog", { name: "UTM templates", exact: true });
  const toggle = page.getByRole("button", { name: /^UTMs/ });
  const source = popup.getByLabel("Source utm_source");
  const templates = popup.getByRole("button", { name: "Templates", exact: true });
  const preview = popup.getByRole("textbox", { name: "Destination URL preview", exact: true });
  let frame = await editorFrame(page);
  let content = await editorContent(page);
  async function open() {
    await toggle.scrollIntoViewIfNeeded();
    frame = await editorFrame(page);
    content = await editorContent(page);
    await toggle.click();
    await expect(popup).toBeVisible();
    expect(await popup.evaluate((element) => element.matches(":modal"))).toBe(true);
    expect(await editorFrame(page)).toEqual(frame);
    expect(await editorContent(page)).toEqual(content);
  }
  async function closed() {
    await expect(popup).not.toBeVisible();
    await expect(toggle).toBeFocused();
    expect(await editorFrame(page)).toEqual(frame);
    expect(await editorContent(page)).toEqual(content);
  }
  await open();
  const initial = await source.inputValue();
  await expect(preview).toHaveAttribute("readonly", "");
  // Native modality keeps the creator inert while the transaction is open.
  await page.locator(".folder-trigger").evaluate((element: HTMLElement) => element.focus({ preventScroll: true }));
  expect(await popup.evaluate((element) => element.contains(document.activeElement))).toBe(true);
  await expect(popup.locator(".folder-trigger, .link-editor-preview, .link-editor-actions")).toHaveCount(0);
  const footer = [templates, popup.getByRole("button", { name: "Cancel", exact: true }), popup.getByRole("button", { name: "Save", exact: true })];
  for (const control of footer) await visibleControl(page, control);
  const boxes = await Promise.all(footer.map((control) => control.boundingBox()));
  expect(boxes[0]!.x + boxes[0]!.width).toBeLessThan(boxes[1]!.x);
  expect(boxes[1]!.x + boxes[1]!.width).toBeLessThan(boxes[2]!.x);
  expect(boxes[0]!.y + boxes[0]!.height / 2).toBeCloseTo(boxes[2]!.y + boxes[2]!.height / 2, 0);
  const beforeUrl = new URL(await preview.inputValue());
  await source.fill("clear-this-parameter");
  await source.fill("");
  const cleared = new URL(await preview.inputValue());
  expect(cleared.searchParams.has("utm_source")).toBe(false);
  expect(cleared.hash).toBe(beforeUrl.hash);
  expect(cleared.searchParams.get("keep")).toBe(beforeUrl.searchParams.get("keep"));
  await source.fill("newsletter with spaces");
  expect(new URL(await preview.inputValue()).searchParams.get("utm_source")).toBe("newsletter with spaces");
  await source.press("Shift+Enter");
  await expect(popup).toBeVisible();
  await popup.getByRole("button", { name: "Cancel", exact: true }).click();
  await closed();
  for (const dismissal of ["close", "escape", "backdrop"] as const) {
    await open();
    await expect(source).toHaveValue(initial);
    await source.fill(`discard-${dismissal}`);
    if (dismissal === "close") await popup.getByRole("button", { name: "Close UTMs", exact: true }).click();
    else if (dismissal === "escape") await source.press("Escape");
    else await page.mouse.click(2, 2);
    await closed();
  }
  await open();
  await expect(source).toHaveValue(initial);
  if (createTemplate) {
    await source.fill("newsletter");
    await templates.click();
    await menu.getByRole("textbox", { name: "Template name", exact: true }).fill("Verification newsletter");
    await menu.getByRole("button", { name: "Save new template", exact: true }).click();
    await expect(menu.getByRole("button", { name: "Verification newsletter", exact: true })).toBeVisible();
    await expect(menu.getByRole("textbox", { name: "Template name", exact: true })).toHaveValue("");
    await menu.getByRole("textbox", { name: "Template name", exact: true }).press("Escape");
    await expect(menu).not.toBeVisible();
    await expect(templates).toBeFocused();
    await expect(popup).toBeVisible();
    await templates.press("Escape");
    await closed();
    await open();
    // Saving a reusable template persists it, but cannot commit this UTM draft.
    await expect(source).toHaveValue(initial);
  }
  await templates.click();
  await expect(menu).toBeVisible();
  await visibleControl(page, menu.getByRole("button", { name: "Verification newsletter", exact: true }));
  await visibleControl(page, menu.getByRole("textbox", { name: "Template name", exact: true }));
  await visibleControl(page, menu.getByRole("button", { name: "Save new template", exact: true }));
  const menuBounds = (await menu.boundingBox())!;
  expect(menuBounds.y).toBeGreaterThanOrEqual(0);
  expect(menuBounds.y + menuBounds.height).toBeLessThanOrEqual(page.viewportSize()!.height);
  await page.screenshot({ path: `test-results/utm-template-menu-${size}.png` });
  await menu.getByRole("button", { name: "Verification newsletter", exact: true }).click();
  await expect(source).toHaveValue("newsletter");
  if (await menu.isVisible()) await menu.getByRole("textbox", { name: "Template name", exact: true }).press("Escape");
  await popup.getByRole("button", { name: "Cancel", exact: true }).click();
  await closed();
  await open();
  await expect(source).toHaveValue(initial);
  await templates.click();
  await menu.getByRole("button", { name: "Verification newsletter", exact: true }).click();
  if (await menu.isVisible()) await menu.getByRole("textbox", { name: "Template name", exact: true }).press("Escape");
  await page.screenshot({ path: `test-results/utm-popup-${size}.png` });
  await popup.getByRole("button", { name: "Save", exact: true }).click();
  await closed();
  await open();
  await expect(source).toHaveValue("newsletter");
  expect(new URL(await preview.inputValue()).searchParams.get("utm_source")).toBe("newsletter");
  await popup.getByRole("button", { name: "Cancel", exact: true }).click();
  await closed();
  page.setDefaultTimeout(0);
}
