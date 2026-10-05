import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "tests/browser",
  workers: 1,
  use: {
    baseURL: process.env.APP_ORIGIN ?? "http://127.0.0.1:3002",
    viewport: { width: 1440, height: 1080 },
  },
  reporter: "list",
});
