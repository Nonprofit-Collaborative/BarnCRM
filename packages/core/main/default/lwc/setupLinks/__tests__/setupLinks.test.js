import { SETUP_PATHS, setupPath, setupValuePath } from 'c/setupLinks';

// One row per Setup page: a path Salesforce changes fails here, and is fixed in setupLinks once.
const EXPECTED = [
  ['apexSettings', '/lightning/setup/ApexSettings/home'],
  ['companyInformation', '/lightning/setup/CompanyProfileInfo/home'],
  ['deliverability', '/lightning/setup/OrgEmailSettings/home'],
  ['duplicateRules', '/lightning/setup/DuplicateRules/home'],
  ['emailTemplates', '/lightning/setup/CommunicationTemplatesEmail/home'],
  ['fiscalYear', '/lightning/setup/ForecastFiscalYear/home'],
  ['installedPackages', '/lightning/setup/ImportedPackage/home'],
  ['lightningPages', '/lightning/setup/FlexiPageList/home'],
  ['objectManager', '/lightning/setup/ObjectManager/home'],
  ['orgWideAddresses', '/lightning/setup/OrgWideEmailAddresses/home'],
  ['permissionSets', '/lightning/setup/PermSets/home'],
  ['users', '/lightning/setup/ManageUsers/home']
];

describe('c/setupLinks', () => {
  it.each(EXPECTED)('%s opens %s', (key, path) => {
    expect(setupPath(key)).toBe(path);
  });

  it('has a test row for every path, and every path is a relative Lightning Setup page', () => {
    expect(Object.keys(SETUP_PATHS).sort()).toEqual(EXPECTED.map(([key]) => key).sort());
    Object.values(SETUP_PATHS).forEach((path) => {
      expect(path).toMatch(/^\/lightning\/setup\/[A-Za-z]+\/home$/);
    });
  });

  it('gives no path for an unknown key, so no link shows', () => {
    expect(setupPath('nothing')).toBeUndefined();
    expect(setupPath(undefined)).toBeUndefined();
  });

  it('links each read-only value from Setup to its Setup page, whatever the case', () => {
    expect(setupValuePath('Name')).toBe('/lightning/setup/CompanyProfileInfo/home');
    expect(setupValuePath('FiscalYearStartMonth')).toBe('/lightning/setup/ForecastFiscalYear/home');
    expect(setupValuePath('BillingCity')).toBeUndefined();
    expect(setupValuePath(null)).toBeUndefined();
  });

  it('cannot be changed at run time', () => {
    expect(Object.isFrozen(SETUP_PATHS)).toBe(true);
  });
});
