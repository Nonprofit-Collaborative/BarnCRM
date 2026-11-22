// Deeper checks for the pages release 1.24 added or moved. Each asserts only what is the same in
// every org that has the page, and changes nothing: no button here saves anything.

const { test, expect, skipUnlessInOrg } = require('./fixtures');

const STAFF_APP = 'BarnCRM';
const ADMIN_APP = 'BarnCRM_Admin_Console';

test('Advanced Reporting home opens, and New Report opens the report builder', async ({
  sf,
  org
}, testInfo) => {
  skipUnlessInOrg(org, STAFF_APP, 'Advanced_Reporting');
  await sf.open(STAFF_APP, '/n/Advanced_Reporting');
  const main = sf.main();
  await expect(main.locator('[data-id="title"]').first()).toHaveText('Advanced Reporting');
  await expect(main.getByRole('tab', { name: 'Dashboards' })).toBeVisible();
  await sf.expectHealthy(testInfo);

  await main.locator('[data-id="new-report"] button').click();
  const builder = main.locator('c-reporting-builder [data-id="builder"]');
  await expect(builder).toBeVisible();
  await expect(builder.locator('h2[data-id="heading"]')).toHaveText('New Report');
  await expect(builder.locator('[data-id="basics"]')).toBeVisible();
  await sf.expectHealthy(testInfo);
});

test('BarnCRM Settings opens with Advanced Reporting under Data', async ({ sf, org }, testInfo) => {
  skipUnlessInOrg(org, ADMIN_APP, 'BarnCRM_Settings');
  test.skip(!org.allTabs.includes('Advanced_Reporting'), 'Advanced Reporting is not installed');
  await sf.open(ADMIN_APP, '/n/BarnCRM_Settings');
  // The section list is a vertical navigation; each group is a section with its heading.
  const dataGroup = sf
    .main()
    .locator('lightning-vertical-navigation-section')
    .filter({ has: sf.page.locator('h2', { hasText: /^\s*Data\s*$/ }) });
  await expect(dataGroup).toHaveCount(1);
  await expect(dataGroup.getByText('Advanced Reporting', { exact: true })).toBeVisible();
  await sf.expectHealthy(testInfo);
});

for (const [tab, title] of [
  ['Payments_Setup', 'Payments Setup'],
  ['Address_Verification_Setup', 'Address Verification Setup']
]) {
  test(`${title} opens`, async ({ sf, org }, testInfo) => {
    skipUnlessInOrg(org, ADMIN_APP, tab);
    await sf.open(ADMIN_APP, `/n/${tab}`);
    await expect(sf.main().locator('[data-id="title"]').first()).toHaveText(title);
    await sf.expectHealthy(testInfo);
  });
}

test('Health Check shows Run Remaining Checks exactly when checks were left', async ({
  sf,
  org
}, testInfo) => {
  skipUnlessInOrg(org, ADMIN_APP, 'Data_Hygiene');
  await sf.open(ADMIN_APP, '/n/Data_Hygiene?c__section=healthCheck');
  const main = sf.main();
  const panel = main.locator('c-health-check-panel');
  const notRun = main.locator('[data-id="health-check-empty"]');
  // A stored run shows in the panel; with none, the empty state offers Run Health Check, which
  // this test does not press (a run stores its result).
  await expect(panel.or(notRun)).toBeVisible();
  if (await notRun.isVisible()) {
    await expect(main.locator('[data-id="run-remaining"]')).toHaveCount(0);
  } else {
    await expect(panel.locator('[data-id="loading"]')).toHaveCount(0);
    const notChecked = panel
      .locator('[data-id="finding-title"]')
      .filter({ hasText: 'Not Checked, Run Again' });
    const runRemaining = panel.locator('[data-id="run-remaining"]');
    await expect(runRemaining).toHaveCount((await notChecked.count()) > 0 ? 1 : 0);
  }
  await sf.expectHealthy(testInfo);
});
