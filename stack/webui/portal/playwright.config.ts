import { defineConfig, devices } from '@playwright/test';

/**
 * Playwright config for ZotPrime Portal E2E tests.
 *
 * Assumes the portal is already running externally and reachable at baseURL.
 * In CI, set PORTAL_BASE_URL accordingly. Locally the default targets the
 * portal container on host port 3045.
 *
 * The portal is intentionally NOT started by Playwright (no `webServer`) so
 * tests can run against any deployment (local container, dev server, or CI
 * stack) without coupling test runs to a specific startup path.
 */
export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: false, // Shared backend state across tests (single user / rate-limit counters)
  workers: 1,
  retries: 0,
  timeout: 30_000,
  expect: {
    timeout: 5_000,
  },
  reporter: [['list']],
  use: {
    baseURL: process.env.PORTAL_BASE_URL ?? 'http://localhost:3045',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    actionTimeout: 10_000,
    navigationTimeout: 15_000,
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});