import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "tests/browser",
  workers: 1,
  retries: 0,
  timeout: 180_000,
  use: {
    actionTimeout: 10_000,
    baseURL: process.env.APP_ORIGIN ?? "http://127.0.0.1:3002",
    viewport: { width: 1440, height: 1050 },
    trace: "retain-on-failure",
    launchOptions: {
      args: [
        "--use-gl=angle",
        "--use-angle=swiftshader",
        "--enable-unsafe-swiftshader",
      ],
    },
  },
});
