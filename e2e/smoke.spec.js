// Opens every tab of every BarnCRM Lightning app, inside that app, and checks the page loads
// clean. The apps and tabs come from the repository's metadata (e2e/lib/metadata.js); an app or
// tab the org does not have is skipped with the reason.

const { test, expect, skipUnlessInOrg } = require('./fixtures');
const { barnApps } = require('./lib/metadata');

for (const app of barnApps()) {
  test.describe(`${app.label} (${app.name})`, () => {
    test('app opens', async ({ sf, org }, testInfo) => {
      skipUnlessInOrg(org, app.name);
      await sf.page.goto(`${org.origin}/lightning/app/c__${app.name}`);
      await sf.waitLoaded();
      await expect(sf.page.locator('.appName').first()).toHaveText(app.label);
      await sf.expectHealthy(testInfo);
    });

    for (const tab of app.tabs) {
      test(`tab ${tab.name}`, async ({ sf, org }, testInfo) => {
        test.skip(tab.platformOnly, 'a Salesforce page with no BarnCRM code on it');
        skipUnlessInOrg(org, app.name, tab.name);
        await sf.open(app.name, tab.path);
        await expect(sf.page.locator('.appName').first()).toHaveText(app.label);
        await sf.expectHealthy(testInfo);
      });
    }
  });
}
