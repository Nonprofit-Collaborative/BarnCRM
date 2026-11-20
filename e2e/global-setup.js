// Signs in once per run and records what the org holds, for every spec to read.
//
// Sign-in: `sf org open --url-only` gives a one-time front-door URL, the browser opens it, and
// the session cookies are saved as Playwright storage state in e2e-results/.auth/<alias>.json
// (gitignored, like everything under e2e-results/). The URL carries a session id, so it is never
// printed, logged or written: errors from this step are rethrown with every URL removed.

const fs = require('fs');
const path = require('path');
const { chromium } = require('@playwright/test');
const { frontDoorUrl, orgShape } = require('./lib/org');
const { authDir, orgAlias, orgFile, stateFile } = require('./lib/paths');

const SIGN_IN_TIMEOUT = 90_000;

function withoutUrls(error) {
  const message = String((error && error.message) || error).replace(/https?:\/\/\S+/g, '<url>');
  return new Error(`Sign-in failed: ${message.split('\n')[0]}`);
}

module.exports = async function globalSetup() {
  const alias = orgAlias();
  fs.mkdirSync(authDir(), { recursive: true });

  const shape = orgShape(alias);

  const browser = await chromium.launch();
  try {
    const context = await browser.newContext();
    const page = await context.newPage();
    try {
      await page.goto(frontDoorUrl(alias), { timeout: SIGN_IN_TIMEOUT });
      // The front door redirects to /lightning (or a page under it) once the session is set.
      await page.waitForURL((url) => /^\/lightning(\/|$)/.test(url.pathname), {
        timeout: SIGN_IN_TIMEOUT
      });
    } catch (error) {
      throw withoutUrls(error);
    }
    const origin = new URL(page.url()).origin;
    await context.storageState({ path: stateFile() });
    fs.writeFileSync(orgFile(), JSON.stringify({ alias, origin, ...shape }, null, 2));
  } finally {
    await browser.close();
  }
  console.log(`Signed in to ${alias}; ${path.relative(process.cwd(), orgFile())} written.`);
};
