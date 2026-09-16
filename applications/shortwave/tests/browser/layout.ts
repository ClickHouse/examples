import { expect, type Page, type Route } from "@playwright/test";

export async function editorFrame(page: Page) {
  return page.locator("dialog.modal[open]").evaluate((dialog) =>
    [dialog, dialog.querySelector(".modal-heading")!, dialog.querySelector(".link-editor-actions")!]
      .map((element) => {
        const { x, y, width, height } = element.getBoundingClientRect();
        return { x, y, width, height };
      }),
  );
}

export async function editorContent(page: Page) {
  return page.locator(".link-editor-form").evaluate((form) => ({
    scrollTop: form.scrollTop,
    scrollHeight: form.scrollHeight,
    boxes: [...form.querySelectorAll(".link-editor-layout, .link-editor-preview, .folder-trigger, .link-editor-actions")].map((element) => element.getBoundingClientRect().toJSON()),
  }));
}

export async function verifyStablePreview(page: Page) {
  page.setDefaultTimeout(15_000);
  let release: (() => void) | undefined;
  let mode: "ready" | "broken" | "unavailable" = "ready";
  const handler = async (route: Route) => {
    if (!route.request().postData()?.includes("preview-layout.example")) return route.continue();
    const responseMode = mode;
    await new Promise<void>((resolve) => { release = resolve; });
    await route.fulfill({ contentType: "application/json", body: JSON.stringify({ result: {
      status: responseMode === "unavailable" ? "unavailable" : "ready",
      title: "A long preview title that spans several lines and must stay within its reserved space ".repeat(4),
      description: "A detailed destination description that must not push the other fields or creator footer down. ".repeat(8),
      siteName: "Preview fixture",
      image: responseMode === "unavailable" ? null : `https://preview-layout.example/${responseMode}.svg`,
      imageAlt: "Preview fixture image",
    } }) });
  };
  await page.route("**/_serverFn/**", handler);
  await page.route("https://preview-layout.example/*.svg", async (route) => {
    if (route.request().url().endsWith("broken.svg")) return route.abort();
    await route.fulfill({ contentType: "image/svg+xml", body: '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="400"><rect width="100" height="400" fill="#faff69"/></svg>' });
  });
  try {
    for (const viewport of [{ width: 1440, height: 1000 }, { width: 390, height: 600 }]) {
      await page.setViewportSize(viewport);
      await page.getByRole("button", { name: "Create a link", exact: true }).click();
      const frame = await editorFrame(page);
      if (viewport.width > 760) {
        const gap = await page.locator(".link-editor-actions").evaluate((footer) => {
          const card = document.querySelector(".destination-preview-card")!.getBoundingClientRect();
          const fields = document.querySelector(".link-editor-fields")!.getBoundingClientRect();
          return footer.getBoundingClientRect().top - Math.max(card.bottom, fields.bottom);
        });
        expect(gap).toBeLessThanOrEqual(25);
      }
      const slots = () => page.locator(".destination-preview").evaluate((preview) => {
        const origin = preview.getBoundingClientRect();
        return [...preview.querySelectorAll(".destination-preview-media, .destination-preview-copy > *")].map((element) => {
          const box = element.getBoundingClientRect();
          return { x: box.x - origin.x, y: box.y - origin.y, width: box.width, height: box.height };
        });
      });
      const empty = await slots();
      for (mode of ["ready", "broken", "unavailable"] as const) {
        release = undefined;
        await page.getByLabel("Destination URL").fill(`preview-layout.example/${mode}?long=${"value".repeat(80)}`);
        await expect(page.locator(".destination-preview-card")).toHaveAttribute("aria-busy", "true");
        expect(await slots()).toEqual(empty);
        expect(await editorFrame(page)).toEqual(frame);
        await expect.poll(() => Boolean(release)).toBe(true);
        release!();
        await expect(page.locator(".destination-preview-card")).toHaveAttribute("aria-busy", "false");
        if (mode === "ready") {
          await expect(page.locator(".destination-preview-image")).toBeVisible();
          await expect.poll(() => page.locator(".destination-preview-image").evaluate((image: HTMLImageElement) => image.complete && image.naturalHeight > 0)).toBe(true);
        } else if (mode === "broken") {
          await expect(page.locator(".destination-preview-placeholder")).toBeVisible();
        } else {
          await expect(page.getByRole("status")).toContainText("Preview unavailable");
        }
        expect(await slots()).toEqual(empty);
        expect(await editorFrame(page)).toEqual(frame);
      }
      await page.getByLabel("Destination URL").fill("");
      expect(await slots()).toEqual(empty);
      expect(await editorFrame(page)).toEqual(frame);
      await page.screenshot({ path: `test-results/stable-preview-${viewport.width}.png` });
      await page.getByRole("button", { name: "Cancel", exact: true }).click();
    }
  } catch (error) {
    if (!page.isClosed()) await page.screenshot({ path: "test-results/stable-preview-failure.png" });
    throw error;
  } finally {
    release?.();
    if (!page.isClosed()) {
      await page.unroute("**/_serverFn/**", handler);
      await page.unroute("https://preview-layout.example/*.svg");
      await page.setViewportSize({ width: 1440, height: 1000 });
      page.setDefaultTimeout(0);
    }
  }
}
