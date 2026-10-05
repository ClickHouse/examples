import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "tests",
  testMatch: "browser*.spec.ts",
  workers: 1,
  use: {
    baseURL: process.env.APP_ORIGIN ?? "http://127.0.0.1:3000",
    headless: true,
    viewport: { width: 1440, height: 1080 },
  },
  timeout: 90000,
});
