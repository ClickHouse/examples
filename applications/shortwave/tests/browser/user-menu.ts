import { expect, type Locator, type Page } from "@playwright/test";

async function actionContrast(action: Locator): Promise<number> {
  return action.evaluate((element) => {
    // Canvas resolves browser color formats, including color-mix and alpha.
    const canvas = document.createElement("canvas");
    canvas.width = canvas.height = 1;
    const context = canvas.getContext("2d", { willReadFrequently: true })!;
    const rgba = (color: string) => {
      context.clearRect(0, 0, 1, 1);
      context.fillStyle = color;
      context.fillRect(0, 0, 1, 1);
      return Array.from(context.getImageData(0, 0, 1, 1).data);
    };
    const composite = (front: number[], back: number[]) =>
      front.slice(0, 3).map((channel, index) =>
        channel * (front[3] / 255) + back[index] * (1 - front[3] / 255),
      );
    const ancestors: Element[] = [];
    for (let ancestor: Element | null = element; ancestor; ancestor = ancestor.parentElement)
      ancestors.unshift(ancestor);
    let background = [255, 255, 255];
    for (const ancestor of ancestors)
      background = composite(rgba(getComputedStyle(ancestor).backgroundColor), background);
    const foreground = composite(rgba(getComputedStyle(element).color), background);
    const luminance = (rgb: number[]) => {
      const linear = rgb.map((channel) => {
        const normalized = channel / 255;
        return normalized <= 0.04045
          ? normalized / 12.92
          : ((normalized + 0.055) / 1.055) ** 2.4;
      });
      return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722;
    };
    const light = luminance(foreground);
    const dark = luminance(background);
    return (Math.max(light, dark) + 0.05) / (Math.min(light, dark) + 0.05);
  });
}

export async function verifyUserMenu(page: Page) {
  const trigger = page.locator(".sidebar-account .cl-userButtonTrigger");
  const popup = page.locator(".cl-userButtonPopoverCard");
  await trigger.click();
  await expect(popup).toBeVisible();
  await page.mouse.move(0, 0);

  const actions = [
    { name: "Manage account", filename: "manage-account" },
    { name: "Sign out", filename: "sign-out" },
  ].map(({ name, filename }) => ({
    name,
    filename,
    button: popup.locator(".cl-userButtonPopoverActionButton").filter({
      hasText: new RegExp(`^\\s*${name}\\s*$`),
    }),
  }));

  for (const { name, button } of actions) {
    await expect(button).toBeVisible();
    await expect.poll(() => actionContrast(button), {
      message: `${name} normal text contrast`,
    }).toBeGreaterThanOrEqual(4.5);
  }
  await popup.screenshot({ path: "test-results/user-menu-normal.png" });

  for (const { name, filename, button } of actions) {
    await button.hover();
    await expect.poll(() => actionContrast(button), {
      message: `${name} hovered text contrast`,
    }).toBeGreaterThanOrEqual(4.5);
    await popup.screenshot({ path: `test-results/user-menu-${filename}-hover.png` });
  }

  await page.mouse.move(0, 0);
  for (const { name, filename, button } of actions) {
    // Traverse with real keyboard input, so :focus-visible is exercised.
    let focused = false;
    for (let step = 0; step < 12; step++) {
      await page.keyboard.press("Tab");
      focused = await button.evaluate((element) =>
        element === document.activeElement && element.matches(":focus-visible"),
      );
      if (focused) break;
    }
    expect(focused, `${name} can receive visible keyboard focus`).toBe(true);
    await expect.poll(() => actionContrast(button), {
      message: `${name} keyboard-focused text contrast`,
    }).toBeGreaterThanOrEqual(4.5);
    await popup.screenshot({ path: `test-results/user-menu-${filename}-focus.png` });
  }

  await page.keyboard.press("Escape");
  await expect(popup).not.toBeVisible();
}
