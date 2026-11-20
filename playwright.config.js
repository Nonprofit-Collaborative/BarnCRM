// Browser smoke tests (plan Q3): run locally against a scratch org, never in CI. Start them with
// `bash scripts/org/run-e2e.sh <alias>`, which sets E2E_ORG. See docs/contributor-guide/e2e.md.
//
// Traces and video stay off: a trace records every request, and the sign-in request carries a
// session id. Screenshots are taken only when a test fails.

const { defineConfig, devices } = require('@playwright/test');

module.exports = defineConfig({
  testDir: 'e2e',
  outputDir: 'e2e-results/artifacts',
  globalSetup: require.resolve('./e2e/global-setup.js'),
  // Each worker keeps one signed-in page for all its tests; one worker keeps a console app's
  // open tabs from being changed by another worker in the same user's session.
  workers: 1,
  fullyParallel: false,
  retries: 0,
  forbidOnly: true,
  // Lightning is slow to boot in a scratch org: a page can take 20 seconds to settle.
  timeout: 120_000,
  expect: { timeout: 45_000 },
  reporter: [['list'], ['json', { outputFile: 'e2e-results/results.json' }]],
  use: {
    ...devices['Desktop Chrome'],
    viewport: { width: 1440, height: 900 },
    headless: true,
    navigationTimeout: 90_000,
    actionTimeout: 30_000,
    screenshot: 'only-on-failure',
    trace: 'off',
    video: 'off'
  },
  projects: [{ name: 'chromium' }]
});
