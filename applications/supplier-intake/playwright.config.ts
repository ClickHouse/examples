import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir: 'tests/browser',
  workers: 1,
  retries: 0,
  timeout: 180_000,
  use: {
    baseURL: process.env.ORIGIN ?? 'http://127.0.0.1:3001',
    browserName: 'chromium',
    viewport: { width: 1440, height: 1050 },
    trace: 'retain-on-failure',
  },
});
