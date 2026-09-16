import { expect, type Locator, type Page } from "@playwright/test";
import { editorContent, editorFrame } from "./layout";

export async function chooseOption(page: Page, control: Locator, label: string) {
  await control.click();
  const option = page.getByRole("option", { name: label, exact: true });
  await option.scrollIntoViewIfNeeded();
  expect(await option.evaluate((element) => {
    const box = element.getBoundingClientRect();
    return element.contains(document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2));
  })).toBe(true);
  const box = (await page.locator(".app-select-options:visible").boundingBox())!;
  expect(box.x).toBeGreaterThanOrEqual(0);
  expect(box.y).toBeGreaterThanOrEqual(0);
  expect(box.x + box.width).toBeLessThanOrEqual(page.viewportSize()!.width);
  expect(box.y + box.height).toBeLessThanOrEqual(page.viewportSize()!.height);
  await option.click();
  await expect(control).toContainText(label);
}

export async function verifyEditorControls(page: Page) {
  const actions = page.locator(".link-editor-actions");
  const buttons = [
    actions.getByRole("button", { name: /^UTMs/ }),
    actions.getByRole("button", { name: "Cancel", exact: true }),
    actions.getByRole("button", { name: /^(Create link|Save changes)$/ }),
  ];
  const boxes = await Promise.all(buttons.map((button) => button.boundingBox()));
  for (const box of boxes) {
    expect(box).not.toBeNull();
    expect(box!.height).toBeCloseTo(boxes[0]!.height, 0);
    expect(box!.y).toBeCloseTo(boxes[0]!.y, 0);
    expect(box!.x).toBeGreaterThanOrEqual(0);
    expect(box!.x + box!.width).toBeLessThanOrEqual(page.viewportSize()!.width);
  }
  expect(boxes[1]!.x - boxes[0]!.x - boxes[0]!.width).toBeGreaterThanOrEqual(7);
  expect(boxes[2]!.x - boxes[1]!.x - boxes[1]!.width).toBeGreaterThanOrEqual(7);
  await expect(page.locator("dialog[open] select")).toHaveCount(0);
}

export async function verifyFolderDisclosure(page: Page) {
  const trigger = page.locator(".folder-trigger");
  const popup = page.locator(".folder-popup");
  await expect(popup).toBeVisible();
  // The floating menu must stay anchored without contributing layout height.
  const { anchor, panel } = await popup.evaluate((element) => {
    const dialog = element.closest("dialog")!;
    return {
      anchor: dialog.querySelector(".folder-trigger")!.getBoundingClientRect().toJSON(),
      panel: element.getBoundingClientRect().toJSON(),
    };
  });
  expect(panel.y).toBeGreaterThanOrEqual(anchor.y + anchor.height + 5);
  expect(panel.x).toBeCloseTo(anchor.x, 0);
  expect(panel.width).toBeCloseTo(anchor.width, 0);
  expect(panel.y + panel.height).toBeLessThanOrEqual(page.viewportSize()!.height - 7);
  expect(anchor.y).toBeGreaterThanOrEqual(0);
  for (const field of [page.getByLabel("Link title"), page.getByRole("combobox", { name: "Tags", exact: true })]) {
    const bounds = (await field.boundingBox())!;
    expect(bounds.y + bounds.height).toBeLessThanOrEqual(anchor.y);
  }
  expect(await trigger.evaluate((element) => {
    const rect = element.getBoundingClientRect();
    return element.contains(document.elementFromPoint(rect.x + rect.width / 2, rect.y + rect.height / 2));
  })).toBe(true);
}

export async function verifyScrollableFolderPicker(page: Page) {
  for (const viewport of [{ width: 1440, height: 1000 }, { width: 390, height: 600 }]) {
    await page.setViewportSize(viewport);
    await page.getByRole("button", { name: "Create a link", exact: true }).click();
    await page.locator(".folder-trigger").evaluate((element) => element.scrollIntoView({ block: "center" }));
    const frame = await editorFrame(page);
    const content = await editorContent(page);
    await page.locator(".folder-trigger").click();
    expect(await editorFrame(page)).toEqual(frame);
    expect(await editorContent(page)).toEqual(content);
    const search = page.getByRole("textbox", { name: "Search or create a folder" });
    await expect(page.locator(".folder-options button")).toHaveCount(13);
    const list = page.locator(".folder-options");
    const listHeight = await list.evaluate((element) => element.clientHeight);
    const visibleRows = await list.evaluate((element) => {
      const bounds = element.getBoundingClientRect();
      return [...element.querySelectorAll("button")].filter((button) => {
        const box = button.getBoundingClientRect();
        return box.top >= bounds.top && box.bottom <= bounds.bottom + 1;
      }).length;
    });
    expect(visibleRows).toBeGreaterThanOrEqual(2);
    expect(visibleRows).toBeLessThanOrEqual(3);
    await search.fill("Picker folder 11");
    await expect(page.locator(".folder-options button")).toHaveCount(2);
    expect(await list.evaluate((element) => element.clientHeight)).toBe(listHeight);
    expect(await editorFrame(page)).toEqual(frame);
    expect(await editorContent(page)).toEqual(content);
    await search.fill("");
    await expect(page.locator(".folder-options button")).toHaveCount(13);
    await verifyFolderDisclosure(page);
    const dialog = page.locator(".link-editor-form");
    const scrollBefore = await dialog.evaluate((element) => element.scrollTop);
    await search.press("ArrowUp");
    const last = page.locator(".folder-options button").last();
    await expect(last).toBeFocused();
    expect(await page.locator(".folder-options").evaluate((element) => element.scrollTop)).toBeGreaterThan(0);
    expect(await dialog.evaluate((element) => element.scrollTop)).toBeCloseTo(scrollBefore, 0);
    await verifyFolderDisclosure(page);
    await page.screenshot({ path: `test-results/folder-selector-scroll-${viewport.width}.png` });
    await page.locator(".folder-trigger").focus();
    await page.locator(".folder-trigger").press("ArrowUp");
    await expect(last).toBeFocused();
    const selectedName = (await last.textContent())!.trim();
    await page.keyboard.press("Enter");
    await expect(page.locator(".folder-trigger")).toContainText(selectedName);
    expect(await editorFrame(page)).toEqual(frame);
    expect(await editorContent(page)).toEqual(content);
    await expect(page.locator(".folder-trigger")).toBeFocused();
    await page.getByRole("button", { name: "Cancel", exact: true }).click();
  }
  await page.setViewportSize({ width: 1440, height: 1000 });
}

/** Existing folder + saved template: each control must retain its own state. */
export async function verifyFolderTemplateIsolation(page: Page, folderName: string, size: string) {
  page.setDefaultTimeout(15_000);
  const trigger = page.locator(".folder-trigger");
  const toggle = page.getByRole("button", { name: /^UTMs/ });
  const panel = page.getByRole("dialog", { name: "UTM parameters", exact: true });
  const templates = panel.getByRole("button", { name: "Templates", exact: true });
  const menu = page.getByRole("dialog", { name: "UTM templates", exact: true });
  const source = page.getByLabel("Source utm_source");
  let frame = await editorFrame(page);
  let content = await editorContent(page);
  async function openUtms() {
    await toggle.scrollIntoViewIfNeeded();
    frame = await editorFrame(page);
    content = await editorContent(page);
    await toggle.click();
    await expect(panel).toBeVisible();
    expect(await panel.evaluate((element) => element instanceof HTMLDialogElement && element.matches(":modal"))).toBe(true);
    expect(await editorFrame(page)).toEqual(frame);
    expect(await editorContent(page)).toEqual(content);
    await expect(panel.getByLabel("Destination URL", { exact: true })).toHaveCount(0);
    await expect(panel.locator(".folder-trigger")).toHaveCount(0);
  }
  async function verifyClosedUtms() {
    await expect(panel).not.toBeVisible();
    await expect(toggle).toBeFocused();
    expect(await editorFrame(page)).toEqual(frame);
    expect(await editorContent(page)).toEqual(content);
  }
  await openUtms();
  await templates.click();
  await menu.getByRole("button", { name: "Verification newsletter", exact: true }).click();
  if (await menu.isVisible()) await menu.getByLabel("Template name", { exact: true }).press("Escape");
  await expect(source).toHaveValue("newsletter");
  await panel.getByRole("button", { name: "Save", exact: true }).click();
  await verifyClosedUtms();
  await openUtms();
  await templates.click();
  await expect(menu).toBeVisible();
  await page.screenshot({ path: `test-results/themed-template-${size}.png`, fullPage: false });
  await menu.getByLabel("Template name", { exact: true }).press("Escape");
  await expect(menu).not.toBeVisible();
  await expect(templates).toBeFocused();
  await expect(panel).toBeVisible();
  await templates.press("Escape");
  await verifyClosedUtms();
  // The creator is inert while the modal UTM overlay is open. Close it
  // before choosing a folder, then reopen it to inspect its retained state.
  await trigger.evaluate((element) => element.scrollIntoView({ block: "center" }));
  expect(await trigger.evaluate((element) => {
    const box = element.getBoundingClientRect();
    return element.contains(document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2));
  })).toBe(true);
  const folderFrame = await editorFrame(page);
  const folderContent = await editorContent(page);
  await trigger.click();
  await expect(panel).not.toBeVisible();
  expect(await editorFrame(page)).toEqual(folderFrame);
  expect(await editorContent(page)).toEqual(folderContent);
  const search = page.getByRole("textbox", { name: "Search or create a folder" });
  await expect(search).toBeFocused();
  await verifyFolderDisclosure(page);
  const option = page.locator(".folder-popup").getByRole("button", { name: folderName, exact: true });
  await expect(option).toBeVisible();
  expect(await option.evaluate((element) => {
    const box = element.getBoundingClientRect();
    return element.contains(document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2));
  })).toBe(true);
  await page.screenshot({ path: `test-results/folder-template-${size}.png`, fullPage: false });
  await page.locator(".folder-popup").getByRole("button", { name: "No folder", exact: true }).click();
  await expect(trigger).toBeFocused();
  await openUtms();
  await expect(source).toHaveValue("newsletter");
  await source.fill(`discarded-${size}`);
  await panel.getByRole("button", { name: "Cancel", exact: true }).click();
  await verifyClosedUtms();
  await openUtms();
  await expect(source).toHaveValue("newsletter");
  await source.fill(`draft-${size}`);
  await panel.getByRole("button", { name: "Save", exact: true }).click();
  await verifyClosedUtms();
  // Folder selection must preserve parameters explicitly saved to the creator.
  await trigger.focus();
  await trigger.press("Enter");
  await expect(panel).not.toBeVisible();
  await search.fill(folderName);
  await search.press("ArrowDown");
  await page.keyboard.press("ArrowDown");
  await expect(option).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(trigger).toContainText(folderName);
  await openUtms();
  await expect(source).toHaveValue(`draft-${size}`);
  await templates.click();
  await expect(menu.getByRole("button", { name: "Verification newsletter", exact: true })).toBeVisible();
  await menu.getByLabel("Template name", { exact: true }).press("Escape");
  await panel.getByRole("button", { name: "Cancel", exact: true }).click();
  await verifyClosedUtms();
  await trigger.click();
  await search.press("Escape");
  await openUtms();
  await expect(search).not.toBeVisible();
  await expect(source).toHaveValue(`draft-${size}`);
  await panel.getByRole("button", { name: "Close UTMs", exact: true }).click();
  await verifyClosedUtms();
  await trigger.click();
  await page.getByLabel("Link title").click();
  await expect(search).not.toBeVisible();
  await expect(page.getByLabel("Link title")).toBeFocused();
  await verifyEditorControls(page);
  page.setDefaultTimeout(0);
}
