import { expect, type Page } from "@playwright/test";

/** Signed-in Links page. Verifies compact filters keep readable, full-width menus. */
export async function verifyDropdowns(page: Page) {
  const originalViewport = page.viewportSize();
  for (const viewport of [{ width: 1440, height: 1000 }, { width: 390, height: 600 }, { width: 320, height: 640 }]) {
    await page.setViewportSize(viewport);
    for (const [name, label] of [["Filter links by folder", "All folders"], ["Filter links by tag", "All tags"]]) {
      const trigger = page.getByRole("combobox", { name, exact: true });
      await trigger.focus();
      await trigger.press("Home");
      await trigger.press("Enter");
      await expect(trigger).toContainText(label);
      await trigger.click();
      const menu = page.getByRole("listbox", { name, exact: true });
      const option = menu.getByRole("option", { name: label, exact: true });
      await expect(option).toBeVisible();
      const triggerBox = (await trigger.boundingBox())!;
      const menuBox = (await menu.boundingBox())!;
      expect(menuBox.width).toBeCloseTo(triggerBox.width, 0);
      expect(menuBox.x).toBeCloseTo(triggerBox.x, 0);
      expect(menuBox.width).toBeGreaterThanOrEqual(150);
      expect(menuBox.x).toBeGreaterThanOrEqual(0);
      expect(menuBox.x + menuBox.width).toBeLessThanOrEqual(viewport.width);
      const geometry = await option.evaluate((element) => {
        const text = element.querySelector("span")!;
        const check = element.querySelector("svg")!;
        const range = document.createRange();
        range.selectNodeContents(text);
        const textBox = range.getBoundingClientRect();
        const checkBox = check.getBoundingClientRect();
        const box = element.getBoundingClientRect();
        return {
          lines: range.getClientRects().length,
          textFits: text.scrollWidth <= text.clientWidth,
          checkGap: checkBox.left - textBox.right,
          hit: element.contains(document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2)),
        };
      });
      expect(geometry.lines).toBe(1);
      expect(geometry.textFits).toBe(true);
      expect(geometry.checkGap).toBeGreaterThanOrEqual(10);
      expect(geometry.hit).toBe(true);
      if (label === "All folders") await page.screenshot({ path: `test-results/dropdown-folders-${viewport.width}.png`, fullPage: false });
      await trigger.press("Escape");
      await expect(menu).not.toBeVisible();
      await expect(trigger).toBeFocused();
    }
    const folders = page.getByRole("combobox", { name: "Filter links by folder", exact: true });
    await folders.press("ArrowDown");
    await folders.press("ArrowDown");
    await folders.press("Enter");
    await expect(folders).toContainText("No folder");
    await folders.press("Home");
    await folders.press("Enter");
    await expect(folders).toContainText("All folders");
  }
  if (originalViewport) await page.setViewportSize(originalViewport);
}
