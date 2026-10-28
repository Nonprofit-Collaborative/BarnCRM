/**
 * Every Salesforce Setup page BarnCRM links to, by a key the components use. One place, so a
 * path Salesforce changes is fixed once. Each path is the Lightning Setup page itself, relative
 * to the org, with no record Id and no namespace. Where Salesforce has no stable link to one
 * record (a single permission set, Lightning page or object), the key opens the list page and
 * the step text says what to pick there.
 */
const SETUP_PATHS = Object.freeze({
  apexSettings: '/lightning/setup/ApexSettings/home',
  companyInformation: '/lightning/setup/CompanyProfileInfo/home',
  deliverability: '/lightning/setup/OrgEmailSettings/home',
  duplicateRules: '/lightning/setup/DuplicateRules/home',
  emailTemplates: '/lightning/setup/CommunicationTemplatesEmail/home',
  fiscalYear: '/lightning/setup/ForecastFiscalYear/home',
  installedPackages: '/lightning/setup/ImportedPackage/home',
  lightningPages: '/lightning/setup/FlexiPageList/home',
  objectManager: '/lightning/setup/ObjectManager/home',
  orgWideAddresses: '/lightning/setup/OrgWideEmailAddresses/home',
  permissionSets: '/lightning/setup/PermSets/home',
  users: '/lightning/setup/ManageUsers/home'
});

/** The Setup page for each read-only value from Setup, by its Setting_Key__c (ADR-0135). */
const SETUP_VALUE_PATHS = Object.freeze({
  name: SETUP_PATHS.companyInformation,
  fiscalyearstartmonth: SETUP_PATHS.fiscalYear
});

/** The path for a key, or undefined when the key is unknown (the caller then shows no link). */
function setupPath(key) {
  return SETUP_PATHS[key];
}

/** The path for a read-only value from Setup, matched without regard to case. */
function setupValuePath(settingKey) {
  return SETUP_VALUE_PATHS[String(settingKey || '').toLowerCase()];
}

export { SETUP_PATHS, setupPath, setupValuePath };
