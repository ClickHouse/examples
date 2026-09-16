import { randomUUID } from "node:crypto";
import { expect, type Page } from "@playwright/test";

/** Uses a real absent TXT lookup; creates no external DNS records. Leaves Links open. */
export async function verifyDomains(page: Page) {
  const hostname = `browser-${randomUUID()}.shortwave.dev`;
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.getByRole("navigation", { name: "Main navigation" }).getByRole("link", { name: "Domains", exact: true }).click();
  await expect(page.getByRole("heading", { name: "Domains", exact: true })).toBeVisible();
  await expect(page.getByRole("heading", { name: "No domains yet", exact: true })).toBeVisible();

  async function add(value: string) {
    await page.getByRole("button", { name: "Add domain", exact: true }).click();
    const dialog = page.getByRole("dialog");
    await expect(dialog.getByLabel("Domain", { exact: true })).toBeFocused();
    await dialog.getByLabel("Domain", { exact: true }).fill(value);
    await dialog.getByRole("button", { name: "Add domain", exact: true }).click();
    await expect(dialog).not.toBeVisible();
  }

  await add(`${hostname.toUpperCase()}.`);
  const card = page.getByRole("article", { name: hostname, exact: true });
  await expect(card).toBeVisible();
  await expect(card.getByText("Pending verification", { exact: true })).toBeVisible();
  const codes = card.locator(".domain-dns-value code");
  const recordName = (await codes.nth(0).textContent())!;
  const recordValue = (await codes.nth(1).textContent())!;
  expect(recordName).toBe(`_shortwave-verification.${hostname}`);
  expect(recordValue).toMatch(/^shortwave-verification=[a-f0-9]{64}$/);

  await page.context().grantPermissions(["clipboard-read", "clipboard-write"]);
  for (const [label, expected] of [["Copy record name", recordName], ["Copy record value", recordValue]]) {
    const copy = card.getByRole("button", { name: label, exact: true });
    await copy.click();
    await expect(copy.locator("xpath=../..").getByRole("status")).toHaveText("Copied");
    await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toBe(expected);
  }
  await page.screenshot({ path: "test-results/domains-desktop.png", fullPage: true });

  await card.getByRole("button", { name: "Check DNS", exact: true }).click();
  await expect(card.getByRole("alert")).toContainText("TXT record not found", { timeout: 15_000 });
  await expect(card.getByText("Pending verification", { exact: true })).toBeVisible();
  await expect(card.locator("time")).toHaveAttribute("datetime", /\d{4}-\d{2}-\d{2}T/);
  await page.reload();
  await expect(card).toBeVisible();
  await expect(codes.nth(0)).toHaveText(recordName);
  await expect(codes.nth(1)).toHaveText(recordValue);
  await expect(card.getByRole("alert")).toContainText("TXT record not found");
  await expect(card.locator("time")).toBeVisible();

  for (const width of [390, 320]) {
    await page.setViewportSize({ width, height: 700 });
    await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
    for (const element of [codes.nth(0), codes.nth(1), card.getByRole("button", { name: "Copy record value", exact: true })]) {
      const bounds = (await element.boundingBox())!;
      expect(bounds.x).toBeGreaterThanOrEqual(0);
      expect(bounds.x + bounds.width).toBeLessThanOrEqual(width);
    }
    await page.screenshot({ path: `test-results/domains-mobile-${width}.png`, fullPage: true });
  }
  const remove = card.getByRole("button", { name: `Remove ${hostname}`, exact: true });
  await remove.click();
  await expect(page.getByRole("heading", { name: "Remove domain?", exact: true })).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(page.getByRole("dialog")).not.toBeVisible();
  await expect(remove).toBeFocused();
  await expect(card).toBeVisible();

  async function removeClaim() {
    await remove.click();
    await page.getByRole("dialog").getByRole("button", { name: "Remove domain", exact: true }).click();
    await expect(card).not.toBeVisible();
    await expect(page.getByRole("heading", { name: "No domains yet", exact: true })).toBeVisible();
  }
  await removeClaim();
  await page.reload();
  await expect(card).not.toBeVisible();
  await add(hostname);
  await expect(card).toBeVisible();
  await expect(codes.nth(0)).toHaveText(recordName);
  await expect(codes.nth(1)).not.toHaveText(recordValue);
  await expect(card.getByText("Pending verification", { exact: true })).toBeVisible();
  await expect(card.locator("time")).toHaveCount(0);
  await removeClaim();
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.goto("/links");
  await expect(page.getByRole("heading", { name: "Your links", exact: true })).toBeVisible();
}
