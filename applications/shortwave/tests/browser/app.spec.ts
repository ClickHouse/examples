import { test, expect, type Page } from "@playwright/test";
import {
  clerk,
  clerkSetup,
  setupClerkTestingToken,
} from "@clerk/testing/playwright";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { PNG } from "pngjs";
import jsQR from "jsqr";
import { closeDatabases, getPostgres } from "../../src/server/db";
import { flushOutbox, getAccountId } from "../../src/server/service";
import { verifyUserMenu } from "./user-menu";
import { verifyFolders } from "./folders";
import { chooseOption, verifyEditorControls, verifyScrollableFolderPicker } from "./controls";
import { verifyDropdowns } from "./dropdowns";
import { verifyStablePreview } from "./layout";
import { verifyUtmTransactions } from "./utms";
import { verifyDomains } from "./domains";

let clerkUserId: string | undefined;
async function verifyTagOverlay(page: Page, size: string) {
  await expect(page.locator(".destination-preview-card")).toHaveAttribute("aria-busy", "false");
  const input = page.getByRole("combobox", { name: "Tags", exact: true });
  const list = page.getByRole("listbox", { name: "Saved tags" });
  const toggle = page.getByRole("button", { name: /^UTMs/ });
  await input.fill("lau");
  await expect(list.getByRole("option", { name: "launch", exact: true })).toBeVisible();
  await input.press("Escape");
  const before = await toggle.boundingBox();
  await input.fill("laun");
  await expect(list).toBeVisible();
  expect((await toggle.boundingBox())!.y).toBeCloseTo(before!.y, 0);
  await input.press("ArrowDown");
  expect((await toggle.boundingBox())!.y).toBeCloseTo(before!.y, 0);
  await input.press("ArrowUp");
  const last = list.getByRole("option").last();
  await expect(last).toHaveAttribute("aria-selected", "true");
  expect(await last.evaluate((option) => {
    const box = option.getBoundingClientRect();
    const menu = option.parentElement!.getBoundingClientRect();
    return box.top >= menu.top && box.bottom <= menu.bottom;
  })).toBe(true);
  expect((await toggle.boundingBox())!.y).toBeCloseTo(before!.y, 0);
  await input.press("ArrowDown");
  const bounds = await list.boundingBox();
  expect(bounds!.x).toBeGreaterThanOrEqual(0);
  expect(bounds!.x + bounds!.width).toBeLessThanOrEqual(page.viewportSize()!.width);
  expect(bounds!.y).toBeGreaterThanOrEqual(0);
  expect(bounds!.y + bounds!.height).toBeLessThanOrEqual(page.viewportSize()!.height);
  // Visible geometry alone misses lists painted behind the dialog/footer.
  expect(await list.getByRole("option", { name: "launch", exact: true }).evaluate((option) => {
    const box = option.getBoundingClientRect();
    return option.contains(document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2));
  })).toBe(true);
  const dialog = page.locator(".link-editor-form");
  const scrollTop = await dialog.evaluate((element) => element.scrollTop);
  await dialog.evaluate((element) => { element.scrollTop += 24; });
  await expect.poll(async () => {
    const anchor = await page.locator(".tag-input-anchor").boundingBox();
    const menu = await list.boundingBox();
    if (!anchor || !menu) return false;
    return Math.min(
      Math.abs(menu.y - (anchor.y + anchor.height + 6)),
      Math.abs(anchor.y - (menu.y + menu.height + 6)),
    ) < 1;
  }).toBe(true);
  await dialog.evaluate((element, value) => { element.scrollTop = value; }, scrollTop);
  await page.screenshot({ path: `test-results/tag-overlay-${size}.png`, fullPage: true });
  await input.press("Escape");
  await expect(list).not.toBeVisible();
  expect((await toggle.boundingBox())!.y).toBeCloseTo(before!.y, 0);
  await expect(page.locator("dialog.modal[open]")).toBeVisible();
  await input.fill("");
  await input.press("Escape");
}

const email = `shortwave-${randomUUID()}+clerk_test@example.com`;
async function clerkApi(path: string, method: string, body?: object) {
  const response = await fetch(`https://api.clerk.com/v1${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${process.env.CLERK_SECRET_KEY}`,
      "Content-Type": "application/json",
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  if (!response.ok) {
    const result = (await response.json()) as {
      errors?: {
        code?: string;
        long_message?: string;
        meta?: { param_name?: string };
      }[];
    };
    throw new Error(
      `Clerk test fixture operation failed (HTTP ${response.status}): ${result.errors?.map((e) => `${e.code}:${e.meta?.param_name || ""}${response.status === 422 ? ` ${e.long_message}` : ""}`).join(", ")}`,
    );
  }
  return response.json() as Promise<{ id: string }>;
}

test.beforeAll(async () => {
  if (!process.env.CLERK_SECRET_KEY?.startsWith("sk_test_"))
    throw new Error("Browser tests require a Clerk development instance.");
  await clerkSetup({ dotenv: false });
  const user = await clerkApi("/users", "POST", {
    email_address: [email],
    username: `shortwave_${randomUUID().replaceAll("-", "").slice(0, 16)}`,
    password: `${randomUUID()}!Aa9`,
    first_name: "Shortwave",
    last_name: "Test",
  });
  clerkUserId = user.id;
});

test.afterAll(async () => {
  try {
    if (clerkUserId) {
      const db = getPostgres();
      const result = await db.query(
        "SELECT id FROM accounts WHERE clerk_user_id = $1",
        [clerkUserId],
      );
      const accountId = result.rows[0]?.id;
      if (accountId) {
        for (const table of [
          "click_outbox",
          "qr_styles",
          "utm_templates",
          "links",
        ])
          await db.query(`DELETE FROM ${table} WHERE account_id = $1`, [
            accountId,
          ]);
        await db.query("DELETE FROM accounts WHERE id = $1", [accountId]);
      }
      await clerkApi(`/users/${clerkUserId}`, "DELETE");
    }
  } finally {
    await closeDatabases();
  }
});

test("public landing, responsive layout, and protected collection", async ({
  page,
}) => {
  await setupClerkTestingToken({ page });
  await page.goto("/");
  await expect(
    page.getByRole("heading", { name: /Small links/ }),
  ).toBeVisible();
  const navigation = page.getByRole("navigation");
  await expect(navigation.getByRole("link", { name: "Get started" })).toHaveAttribute("href", /sign-up/);
  await expect(navigation.getByRole("link", { name: /Sign in|The possibilities|Dashboard/ })).toHaveCount(0);
  await expect(page.locator('link[rel="icon"]')).toHaveAttribute("href", "/favicon.svg");
  const favicon = await page.request.get("/favicon.svg");
  expect(favicon.status()).toBe(200);
  expect(favicon.headers()["content-type"]).toContain("image/svg+xml");
  await expect(page.locator(".landing-footer .brand")).toHaveCSS("color", "rgb(255, 255, 255)");
  await page.screenshot({
    path: "test-results/landing-desktop.png",
    fullPage: true,
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await expect(navigation.getByRole("link", { name: "Get started" })).toBeVisible();
  await expect
    .poll(() =>
      page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
    )
    .toBe(true);
  await page.screenshot({
    path: "test-results/landing-mobile.png",
    fullPage: true,
  });
  await page.goto("/links");
  await expect(
    page.getByRole("heading", { name: "Your links", exact: true }),
  ).not.toBeVisible();
  await expect(page.getByText(/Sign in/i).first()).toBeVisible();
  await page.goto("/domains");
  await expect(page.getByRole("heading", { name: "Domains", exact: true })).not.toBeVisible();
  await expect(page.getByText(/Sign in/i).first()).toBeVisible();
});

test("Clerk account creates, edits, tracks and disables a link with a decodable QR", async ({
  page,
  request,
}) => {
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto("/");
  await clerk.signIn({ page, emailAddress: email });
  await page.reload();
  await expect(page.getByRole("navigation").getByRole("link", { name: "Dashboard" })).toHaveAttribute("href", "/links");
  await expect(page.getByRole("navigation").getByRole("link", { name: "Get started" })).toHaveCount(0);
  await page.setViewportSize({ width: 390, height: 844 });
  await expect(page.getByRole("navigation").getByRole("link", { name: "Dashboard" })).toBeVisible();
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.goto("/links");
  await expect(
    page.getByRole("heading", { name: "Your links", exact: true }),
  ).toBeVisible();
  await verifyUserMenu(page);
  await verifyDropdowns(page);
  await verifyStablePreview(page);
  await page.getByRole("combobox", { name: "Filter links by folder", exact: true }).blur();
  await expect(page.getByText("WORKSPACE", { exact: true })).toHaveCount(0);
  await expect(page.getByText("Your personal collection", { exact: true })).toHaveCount(0);
  await expect(page.locator(".links-banner")).toHaveCount(0);
  const credits = page.locator(".sidebar-credits");
  await expect(credits.getByRole("link", { name: "ClickHouse Cloud", exact: true })).toHaveAttribute("href", "https://clickhouse.com/cloud");
  await expect(credits.getByRole("link", { name: /GitHub/ })).toHaveCount(0);
  expect(await credits.evaluate((element) => element.nextElementSibling?.classList.contains("sidebar-account"))).toBe(true);
  for (const selector of [".workspace-label", ".sidebar-account", ".app-footer"]) {
    expect(await page.locator(selector).evaluate((element) => {
      const style = getComputedStyle(element);
      return style.borderTopWidth === "0px" && style.borderBottomWidth === "0px";
    })).toBe(true);
  }
  await page.keyboard.press("?");
  await expect(page.getByRole("heading", { name: "Keyboard shortcuts", exact: true })).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(page.getByRole("heading", { name: "Keyboard shortcuts", exact: true })).not.toBeVisible();
  await page.keyboard.press("/");
  await expect(page.locator(".search-field input")).toBeFocused();
  await page.keyboard.type("c?");
  await expect(page.locator("dialog.modal[open]")).not.toBeVisible();
  await page.locator(".search-field input").fill("");
  await page.locator(".search-field input").blur();
  await page.keyboard.press("c");
  await expect(page.locator("dialog.modal[open]")).toBeVisible();
  await page.getByLabel("Destination URL").press("Shift+Enter");
  await expect(page.locator("dialog.modal[open]")).toBeVisible();
  expect(await page.getByLabel("Destination URL").evaluate((element: HTMLInputElement) => element.validity.valueMissing)).toBe(true);
  await page
    .getByLabel("Destination URL")
    .fill("example.com/launch?keep=yes&utm_source=old#section");
  await page.getByLabel("Link title").fill("Browser verification");
  await expect(page.getByLabel("Destination URL")).toHaveValue("https://example.com/launch?keep=yes&utm_source=old#section");
  const fieldsBox = (await page.locator(".link-editor-fields").boundingBox())!;
  const previewBox = (await page.locator(".link-editor-preview").boundingBox())!;
  expect(previewBox.x).toBeGreaterThan(fieldsBox.x + fieldsBox.width);
  await page.getByLabel("Link title").dispatchEvent("keydown", { key: "Enter", shiftKey: true, isComposing: true });
  await page.getByLabel("Link title").dispatchEvent("keydown", { key: "Enter", shiftKey: true, repeat: true });
  await expect(page.locator("dialog.modal[open]")).toBeVisible();
  const slug = `browser-${randomUUID().slice(0, 8)}`;
  await page.getByLabel("Short link ending").fill(slug);
  const tagInput = page.getByRole("combobox", { name: "Tags", exact: true });
  const savedTags = page.getByRole("listbox", { name: "Saved tags" });
  await tagInput.fill("verification");
  await tagInput.press("Shift+Enter");
  await expect(page.locator("dialog.modal[open]")).toBeVisible();
  await expect(page.getByRole("button", { name: "Remove tag verification", exact: true })).toBeVisible();
  await tagInput.fill("launch");
  await tagInput.press("Enter");
  await tagInput.press("Backspace");
  await expect(tagInput).toHaveValue("launch");
  await tagInput.press("Enter");
  await tagInput.fill("launch");
  await tagInput.press("Enter");
  await expect(page.getByRole("button", { name: "Remove tag launch", exact: true })).toHaveCount(1);
  await expect(page.getByLabel("Source utm_source")).not.toBeVisible();
  await verifyUtmTransactions(page, "desktop", true);
  await verifyEditorControls(page);
  await page.screenshot({ path: "test-results/link-editor-desktop.png", fullPage: true });
  await page.getByLabel("Destination URL").press("Shift+Enter");
  await expect(page.locator("dialog.modal[open]")).not.toBeVisible();
  await expect(
    page.getByRole("button", { name: "Browser verification", exact: true }),
  ).toBeVisible();
  const redirect = await request.get(`/r/${slug}`, { maxRedirects: 0 });
  expect(redirect.status()).toBe(302);
  expect(redirect.headers()["cache-control"]).toContain("no-store");
  expect(redirect.headers().location).toContain("utm_source=newsletter");
  const accountId = await getAccountId(clerkUserId!);
  expect((await getPostgres().query("SELECT count(*)::int AS count FROM links WHERE account_id = $1 AND title = $2", [accountId, "Browser verification"])).rows[0].count).toBe(1);
  await flushOutbox(500, accountId);

  await page
    .getByRole("button", {
      name: "QR code for Browser verification",
      exact: true,
    })
    .click();
  page.setDefaultTimeout(15_000);
  await expect(page.getByRole("button", { name: "Remove logo", exact: true })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Remove custom logo", exact: true })).toHaveCount(0);
  await chooseOption(page, page.getByLabel("Dot style"), "Soft corners");
  await page.getByRole("button", { name: "Save style", exact: true }).click();
  await expect(
    page.getByRole("button", { name: "Style saved", exact: true }),
  ).toBeVisible();
  expect((await getPostgres().query("SELECT style FROM qr_styles WHERE account_id = $1 AND link_id = (SELECT id FROM links WHERE account_id = $1 AND slug = $2)", [accountId, slug])).rows[0].style.logo).toBe("clickhouse");
  const downloadPromise = page.waitForEvent("download");
  await page.getByRole("button", { name: "PNG", exact: true }).click();
  const download = await downloadPromise;
  const png = PNG.sync.read(await readFile((await download.path())!));
  const decoded = jsQR(new Uint8ClampedArray(png.data), png.width, png.height);
  expect(decoded?.data).toBe(`${process.env.BROWSER_BASE_URL || "http://localhost:4317"}/r/${slug}`);
  const svgDownloadPromise = page.waitForEvent("download");
  await page.getByRole("button", { name: "SVG", exact: true }).click();
  const svgDownload = await svgDownloadPromise;
  const svg = await readFile((await svgDownload.path())!, "utf8");
  expect(svg).toContain("<image");
  expect(svg).toContain("data:image/svg+xml");
  const exportedLogo = async (source: string) => page.evaluate((source) => {
    const doc = new DOMParser().parseFromString(source, "image/svg+xml");
    const image = doc.querySelector("image")!;
    const uri = image.getAttribute("href") || image.getAttributeNS("http://www.w3.org/1999/xlink", "href")!;
    return decodeURIComponent(uri.slice(uri.indexOf(",") + 1));
  }, source);
  const lightLogo = await exportedLogo(svg);
  expect(lightLogo).toContain('fill="#000000"');
  expect(lightLogo).not.toContain("<rect");
  await page.screenshot({ path: "test-results/qr-clickhouse-default.png" });
  await page.getByLabel("Code color").fill("#ffffff");
  await page.getByLabel("Background").fill("#171717");
  const darkSvgPromise = page.waitForEvent("download");
  await page.getByRole("button", { name: "SVG", exact: true }).click();
  const darkSvg = await darkSvgPromise;
  const darkLogo = await exportedLogo(await readFile((await darkSvg.path())!, "utf8"));
  expect(darkLogo).toContain('fill="#ffffff"');
  expect(darkLogo).not.toContain("<rect");
  await page.screenshot({ path: "test-results/qr-clickhouse-dark.png" });
  // A custom raster can replace the built-in mark; removing it restores the mark.
  const customLogo = new PNG({ width: 8, height: 8 });
  customLogo.data.fill(255);
  await page.locator('.qr-controls input[type="file"]').setInputFiles({
    name: "custom-logo.png", mimeType: "image/png", buffer: PNG.sync.write(customLogo),
  });
  await expect(page.getByRole("button", { name: "Remove custom logo", exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Save style", exact: true }).click();
  await expect(page.getByRole("button", { name: "Style saved", exact: true })).toBeVisible();
  expect((await getPostgres().query("SELECT style FROM qr_styles WHERE account_id = $1 AND link_id = (SELECT id FROM links WHERE account_id = $1 AND slug = $2)", [accountId, slug])).rows[0].style.logo).toMatch(/^data:image\/png;base64,/);
  await page.getByRole("button", { name: "Close dialog" }).click();
  await page.reload();
  await page.getByRole("button", { name: "QR code for Browser verification", exact: true }).click();
  await page.getByRole("button", { name: "Remove custom logo", exact: true }).click();
  await expect(page.getByRole("button", { name: "Remove custom logo", exact: true })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Remove logo", exact: true })).toHaveCount(0);
  await page.getByRole("button", { name: "Save style", exact: true }).click();
  await expect(page.getByRole("button", { name: "Style saved", exact: true })).toBeVisible();
  expect((await getPostgres().query("SELECT style FROM qr_styles WHERE account_id = $1 AND link_id = (SELECT id FROM links WHERE account_id = $1 AND slug = $2)", [accountId, slug])).rows[0].style.logo).toBe("clickhouse");
  await page.getByRole("button", { name: "Close dialog" }).click();
  await page.reload();
  await page.getByRole("button", { name: "QR code for Browser verification", exact: true }).click();
  await expect(page.getByRole("button", { name: "Remove custom logo", exact: true })).toHaveCount(0);
  const restoredSvgPromise = page.waitForEvent("download");
  await page.getByRole("button", { name: "SVG", exact: true }).click();
  const restoredSvg = await restoredSvgPromise;
  const restoredLogo = await exportedLogo(await readFile((await restoredSvg.path())!, "utf8"));
  expect(restoredLogo).toContain('fill="#ffffff"');
  expect(restoredLogo).not.toContain("<rect");
  await page.getByRole("button", { name: "Close dialog" }).click();
  page.setDefaultTimeout(0);
  await page.screenshot({
    path: "test-results/links-desktop.png",
    fullPage: true,
  });
  // Publication candidate: only synthetic links, excluding the account sidebar.
  await page.locator(".app-content").screenshot({ path: "test-results/readme-app.png" });

  await page
    .getByRole("button", { name: "Edit Browser verification", exact: true })
    .click();
  await expect(page.getByRole("button", { name: "Remove tag verification", exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Remove tag launch", exact: true }).click();
  await page.getByLabel("Destination URL").fill("https://example.com/updated");
  await expect(page.getByRole("button", { name: "Save changes", exact: true }).locator("svg")).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Save changes", exact: true })).toHaveAttribute("aria-keyshortcuts", "Shift+Enter");
  await page.getByLabel("Destination URL").press("Shift+Enter");
  await expect(page.locator("dialog.modal[open]")).not.toBeVisible();
  await clerk.signOut({ page });
  await page.goto("/");
  await clerk.signIn({ page, emailAddress: email });
  await page.goto("/links");
  await getPostgres().query(
    "INSERT INTO account_tags (account_id, name) SELECT $1, unnest($2::text[]) ON CONFLICT DO NOTHING",
    [accountId, Array.from({ length: 18 }, (_, index) => `launch-check-${String(index).padStart(2, "0")}`)],
  );
  await page.getByRole("button", { name: "Create a link", exact: true }).click();
  await page.getByLabel("Destination URL").fill("https://example.com/reuse");
  await page.getByLabel("Link title").fill("Reused tags");
  await verifyTagOverlay(page, "desktop");
  await page.setViewportSize({ width: 390, height: 844 });
  await verifyTagOverlay(page, "mobile");
  await page.setViewportSize({ width: 390, height: 600 });
  await verifyTagOverlay(page, "mobile-compact");
  await page.setViewportSize({ width: 390, height: 844 });
  await verifyUtmTransactions(page, "mobile");
  await page.setViewportSize({ width: 1440, height: 1000 });
  await tagInput.fill("lau");
  await expect(tagInput).toBeFocused();
  await expect(savedTags.getByRole("option", { name: "launch", exact: true })).toBeVisible();
  await tagInput.press("Escape");
  await expect(page.locator("dialog.modal[open]")).toBeVisible();
  await expect(savedTags.getByRole("option", { name: "launch", exact: true })).not.toBeVisible();
  await tagInput.fill("laun");
  await expect(savedTags.getByRole("option", { name: "launch", exact: true })).toBeVisible();
  await tagInput.press("ArrowDown");
  await tagInput.press("Enter");
  await expect(page.getByRole("button", { name: "Remove tag launch", exact: true })).toBeVisible();
  await tagInput.fill("ver");
  await savedTags.getByRole("option", { name: "verification", exact: true }).click();
  await page.setViewportSize({ width: 390, height: 844 });
  await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  const mobileFields = (await page.locator(".link-editor-fields").boundingBox())!;
  const mobilePreview = (await page.locator(".link-editor-preview").boundingBox())!;
  expect(mobilePreview.y).toBeGreaterThan(mobileFields.y + mobileFields.height);
  await verifyEditorControls(page);
  await page.screenshot({ path: "test-results/link-editor-mobile.png", fullPage: true });
  await page.getByRole("button", { name: "Create link", exact: true }).click();
  await expect(page.locator("dialog.modal[open]")).not.toBeVisible();
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.reload();
  await page.getByRole("button", { name: "Edit Reused tags", exact: true }).click();
  await expect(page.getByRole("button", { name: "Remove tag launch", exact: true })).toBeVisible();
  await expect(page.getByRole("button", { name: "Remove tag verification", exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Cancel", exact: true }).click();
  const edited = await request.get(`/r/${slug}`, { maxRedirects: 0 });
  expect(edited.headers().location).toContain("https://example.com/updated");
  await page
    .getByRole("button", { name: "Edit Browser verification", exact: true })
    .click();
  await page.getByRole("checkbox", { name: /Link is active/ }).uncheck();
  await page.getByRole("button", { name: "Save changes", exact: true }).click();
  await expect(page.locator("dialog.modal[open]")).not.toBeVisible();
  expect((await request.get(`/r/${slug}`, { maxRedirects: 0 })).status()).toBe(
    410,
  );
  await flushOutbox(500, accountId);
  const pickerFolders = await getPostgres().query(
    "INSERT INTO folders (account_id, name) SELECT $1, unnest($2::text[]) RETURNING id",
    [accountId, Array.from({ length: 12 }, (_, index) => `Picker folder ${String(index + 1).padStart(2, "0")}`)],
  );
  try {
    await verifyScrollableFolderPicker(page);
  } finally {
    await getPostgres().query("DELETE FROM folders WHERE account_id = $1 AND id = ANY($2::uuid[])", [accountId, pickerFolders.rows.map((row) => row.id)]);
  }
  await verifyFolders(page);
  await verifyDomains(page);
  await page.goto("/analytics");
  await expect(page.getByRole("heading", { name: "Link analytics", exact: true })).toBeVisible();
  const total = page
    .locator(".stat-card")
    .filter({ hasText: "Total clicks" })
    .locator("strong");
  await expect(total).toHaveText("2");
  await chooseOption(page, page.getByRole("combobox", { name: "Filter by tag", exact: true }), "verification");
  // ClickPipes is asynchronous. Exercise the user's Refresh action until the
  // newly created link's metadata arrives, rather than assuming immediate CDC.
  await expect.poll(async () => {
    await page.getByRole("button", { name: "Refresh", exact: true }).click();
    await expect(page.getByRole("button", { name: "Refresh", exact: true })).toBeEnabled();
    return total.textContent();
  }, { timeout: 60_000, intervals: [2_000, 3_000, 5_000] }).toBe("2");
  await page.screenshot({
    path: "test-results/analytics-desktop.png",
    fullPage: true,
  });
  expect(errors).toEqual([]);
});
