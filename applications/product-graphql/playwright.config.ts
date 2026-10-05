import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "tests/browser",
  use: {
    baseURL: "http://127.0.0.1:3001",
    viewport: { width: 1440, height: 1080 },
  },
  workers: 1,
  timeout: 30000,
});
