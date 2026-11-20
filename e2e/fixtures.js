// The `sf` fixture: one signed-in browser context per worker, reused by every test in it so
// Lightning's scripts load from the browser cache instead of afresh for each page. Each test
// gets the same page with console listening reset, and a screenshot when it fails.

const fs = require('fs');
const base = require('@playwright/test');
const { Lightning } = require('./lib/lightning');
const { orgFile, stateFile } = require('./lib/paths');

const test = base.test.extend({
  org: [
    // eslint-disable-next-line no-empty-pattern
    async ({}, use) => {
      await use(JSON.parse(fs.readFileSync(orgFile(), 'utf8')));
    },
    { scope: 'worker' }
  ],

  sfContext: [
    async ({ browser }, use) => {
      const context = await browser.newContext({
        storageState: stateFile(),
        viewport: { width: 1440, height: 900 }
      });
      await use(context);
      await context.close();
    },
    { scope: 'worker' }
  ],

  sf: async ({ sfContext, org }, use, testInfo) => {
    const open = sfContext.pages().filter((page) => !page.isClosed());
    const page = open[0] || (await sfContext.newPage());
    const sf = new Lightning(page, org);
    sf.listen();
    await use(sf);
    sf.stopListening();
    if (testInfo.status !== testInfo.expectedStatus && !page.isClosed()) {
      const file = testInfo.outputPath('failure.png');
      await page.screenshot({ path: file }).catch(() => {});
      testInfo.attachments.push({ name: 'screenshot', path: file, contentType: 'image/png' });
    }
  }
});

/** Skips the test when the org lacks the app or the tab, saying which and why. */
function skipUnlessInOrg(org, app, tab) {
  test.skip(!org.apps.includes(app), `app ${app} is not in this org`);
  if (!tab) {
    return;
  }
  test.skip(
    !tab.startsWith('standard-') && !org.allTabs.includes(tab),
    `module not installed: tab ${tab} is not in this org`
  );
  test.skip(
    !org.visibleTabs.includes(tab),
    `tab ${tab} is hidden for this user (its feature is off, or no permission set grants it)`
  );
}

module.exports = { test, expect: base.expect, skipUnlessInOrg };
