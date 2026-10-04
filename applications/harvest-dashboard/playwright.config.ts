import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir: './tests/browser', workers: 1, retries: 0, timeout: 120_000,
  use: { baseURL: process.env.APP_ORIGIN ?? 'http://127.0.0.1:3000', browserName: 'chromium', viewport: { width: 1440, height: 1100 }, trace: 'retain-on-failure' },
  reporter: [['list']],
});
