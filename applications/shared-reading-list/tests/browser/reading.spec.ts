import { test, expect } from "@playwright/test";
test("two readers save, find and edit one link", async ({ browser }) => {
  const suffix = crypto.randomUUID();
  const contextA = await browser.newContext();
  const contextB = await browser.newContext();
  const a = await contextA.newPage();
  const b = await contextB.newPage();
  async function signup(page, name) {
    await page.goto("/sign-in");
    await page
      .getByRole("button", { name: "Create an account", exact: true })
      .click();
    await page.getByLabel("Your name").fill(name);
    await page
      .getByLabel("Email", { exact: true })
      .fill(`${name}-${suffix}@example.invalid`);
    await page.getByLabel("Password").fill(`Strong-password-${suffix}`);
    await page
      .getByRole("button", { name: "Create account", exact: true })
      .click();
    await expect(
      page.getByRole("heading", { name: "Good things to read." }),
    ).toBeVisible();
  }
  await signup(a, "Browser-A");
  await signup(b, "Browser-B");
  await a.getByLabel("Title", { exact: true }).fill("Database reading club");
  await a
    .getByLabel("URL", { exact: true })
    .fill(`https://example.com/browser-${suffix}`);
  await a
    .getByLabel("Why it’s worth reading")
    .fill("An introduction to database transactions");
  await a.getByLabel("Tags, separated by commas").fill("postgres, reading");
  await a.getByRole("button", { name: "Save link", exact: true }).click();
  await expect(
    a.getByRole("heading", { name: "Database reading club", exact: true }),
  ).toBeVisible();
  const detail = a.url();
  await b.goto(detail);
  await expect(b.getByRole("heading", { name: "Edit your link" })).toHaveCount(
    0,
  );
  await expect(
    b.getByText("The person who saved this link can edit or delete it."),
  ).toBeVisible();
  await a.getByLabel("Title", { exact: true }).fill("Postgres reading club");
  await a.getByLabel("Tags, separated by commas").fill("postgres, revised");
  await a.getByRole("button", { name: "Save changes" }).click();
  await expect(
    a.getByRole("heading", { name: "Postgres reading club", exact: true }),
  ).toBeVisible();
  await b.goto("/");
  await b.getByLabel("Search title and notes").fill("postgres");
  await b.getByLabel("Tag", { exact: true }).fill("revised");
  await b.getByRole("button", { name: "Find links" }).click();
  await expect(b).toHaveURL(/\?q=postgres&tag=revised/);
  await expect(b.locator("article.card")).toHaveCount(1);
  await expect(
    b.getByRole("heading", { name: "Postgres reading club", exact: true }),
  ).toBeVisible();
  await b.screenshot({
    path: process.env.SCREENSHOT_PATH ?? "/tmp/reading-list.png",
    fullPage: true,
  });
  await a.getByRole("button", { name: "Delete link", exact: true }).click();
  await expect(
    a.getByRole("heading", { name: "Good things to read." }),
  ).toBeVisible();
  await contextA.close();
  await contextB.close();
});
