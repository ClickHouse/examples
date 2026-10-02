import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "tests/browser",
  workers: 1,
  timeout: 120_000,
  expect: { timeout: 30_000 },
  use: {
    baseURL: process.env.TEST_BASE_URL ?? "http://localhost:3000",
    headless: true,
  },
  reporter: "list",
});
