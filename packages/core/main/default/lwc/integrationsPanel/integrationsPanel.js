import { LightningElement, api } from 'lwc';
import getApps from '@salesforce/apex/IntegrationController.getApps';

import INTRO from '@salesforce/label/c.Core_Integrations_Intro';
import GROUP_COMPLEMENT from '@salesforce/label/c.Core_Integrations_GroupComplement';
import GROUP_COMPLEMENT_INTRO from '@salesforce/label/c.Core_Integrations_GroupComplementIntro';
import GROUP_IN_DEVELOPMENT from '@salesforce/label/c.Core_Integrations_GroupInDevelopment';
import GROUP_IN_DEVELOPMENT_INTRO from '@salesforce/label/c.Core_Integrations_GroupInDevelopmentIntro';
import GROUP_ALTERNATIVE from '@salesforce/label/c.Core_Integrations_GroupAlternative';
import GROUP_ALTERNATIVE_INTRO from '@salesforce/label/c.Core_Integrations_GroupAlternativeIntro';
import INSTALLED from '@salesforce/label/c.Core_Integrations_Installed';
import NOT_INSTALLED from '@salesforce/label/c.Core_Integrations_NotInstalled';
import STATUS_IN_PROGRESS from '@salesforce/label/c.Core_Integrations_StatusInProgress';
import STATUS_AVAILABLE from '@salesforce/label/c.Core_Integrations_StatusAvailable';
import REQUEST_HEADING from '@salesforce/label/c.Core_Integrations_RequestHeading';
import REQUEST_INTRO from '@salesforce/label/c.Core_Integrations_RequestIntro';
import REQUEST_LINK from '@salesforce/label/c.Core_Integrations_RequestLink';
import REQUEST_URL from '@salesforce/label/c.Core_Integrations_RequestUrl';
import PARTNER_INTRO from '@salesforce/label/c.Core_Integrations_PartnerIntro';
import PARTNER_LINK from '@salesforce/label/c.Core_Integrations_PartnerLink';
import PARTNER_URL from '@salesforce/label/c.Core_Integrations_PartnerUrl';
import GUIDE_LINK from '@salesforce/label/c.Core_Integrations_GuideLink';
import GUIDE_URL from '@salesforce/label/c.Core_Integrations_GuideUrl';
import MAINTAINER from '@salesforce/label/c.Core_Integrations_Maintainer';
import LICENSE_COST from '@salesforce/label/c.Core_Integrations_LicenseCost';
import RELATED_MODULE from '@salesforce/label/c.Core_Integrations_RelatedModule';
import COMPATIBILITY_HEADING from '@salesforce/label/c.Core_Integrations_CompatibilityHeading';
import MIGRATION_PATH from '@salesforce/label/c.Core_Integrations_MigrationPath';
import LEARN_MORE from '@salesforce/label/c.Core_Integrations_LearnMore';
import INSTALL_LINK from '@salesforce/label/c.Core_Integrations_InstallLink';
import EMPTY from '@salesforce/label/c.Core_Integrations_EmptyMessage';
import LOAD_ERROR from '@salesforce/label/c.Core_Integrations_LoadErrorMessage';
import NEW_TAB from '@salesforce/label/c.Core_SuiteChoice_NewTab';
import CHECK_AGAIN from '@salesforce/label/c.Core_SuiteChoice_CheckAgain';

/** The groups in the order the page shows them, by the category a catalog row stores. */
const GROUPS = [
  { category: 'Complement', heading: GROUP_COMPLEMENT, intro: GROUP_COMPLEMENT_INTRO },
  {
    category: 'InDevelopment',
    heading: GROUP_IN_DEVELOPMENT,
    intro: GROUP_IN_DEVELOPMENT_INTRO
  },
  { category: 'Alternative', heading: GROUP_ALTERNATIVE, intro: GROUP_ALTERNATIVE_INTRO }
];

/** The group a product is drawn in: its category, or the first group for one nobody named. */
function groupOf(app) {
  return GROUPS.some((group) => group.category === app.category)
    ? app.category
    : GROUPS[0].category;
}

/** A label with one {0} placeholder filled in. */
function fill(label, value) {
  return label.replace('{0}', value);
}

/**
 * The Settings, Integrations page: other products that complement BarnCRM or overlap one of its
 * modules, grouped, each with whether it is installed, a note on using the two together, and a
 * link opened in a new tab. The catalog is custom metadata read by Apex; nothing here depends
 * on any of the products. A group with no product is not drawn, so an org without a product
 * that matches a BarnCRM module sees no heading for it.
 */
export default class IntegrationsPanel extends LightningElement {
  apps;
  errorMessage;

  labels = {
    intro: INTRO,
    compatibility: COMPATIBILITY_HEADING,
    empty: EMPTY,
    checkAgain: CHECK_AGAIN,
    newTab: NEW_TAB
  };

  /** The request section at the bottom: one path for organizations, one for providers. */
  request = {
    heading: REQUEST_HEADING,
    intro: REQUEST_INTRO,
    requestLink: REQUEST_LINK,
    requestUrl: REQUEST_URL,
    partnerIntro: PARTNER_INTRO,
    partnerLink: PARTNER_LINK,
    partnerUrl: PARTNER_URL,
    guideLink: GUIDE_LINK,
    guideUrl: GUIDE_URL
  };

  connectedCallback() {
    this.load();
  }

  /** The console calls this after first-run setup finishes, because this row stays mounted. */
  @api
  refresh() {
    return this.load();
  }

  async load() {
    try {
      this.apps = await getApps();
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage =
        error && error.body && error.body.message ? error.body.message : LOAD_ERROR;
    }
  }

  handleCheckAgain() {
    return this.load();
  }

  get isEmpty() {
    return Array.isArray(this.apps) && this.apps.length === 0;
  }

  get groups() {
    const apps = this.apps || [];
    return GROUPS.map((group) => ({
      key: group.category,
      heading: group.heading,
      intro: group.intro,
      apps: apps.filter((app) => groupOf(app) === group.category).map((app) => this.rowFor(app))
    })).filter((group) => group.apps.length > 0);
  }

  rowFor(app) {
    return {
      ...app,
      statusText: app.status === 'Available' ? STATUS_AVAILABLE : STATUS_IN_PROGRESS,
      statusClass:
        app.status === 'Available'
          ? 'slds-badge slds-theme_success slds-var-m-left_x-small'
          : 'slds-badge slds-theme_warning slds-var-m-left_x-small',
      badgeText: app.installed ? INSTALLED : NOT_INSTALLED,
      badgeClass: app.installed
        ? 'slds-badge slds-theme_success slds-var-m-left_x-small'
        : 'slds-badge slds-var-m-left_x-small',
      maintainerText: app.maintainer ? fill(MAINTAINER, app.maintainer) : null,
      licenseCostText: app.licenseCost ? fill(LICENSE_COST, app.licenseCost) : null,
      relatedModuleText: app.relatedModule ? fill(RELATED_MODULE, app.relatedModule) : null,
      migrationPathText: app.migrationPath ? fill(MIGRATION_PATH, app.migrationPath) : null,
      learnMore: LEARN_MORE,
      installLink: INSTALL_LINK,
      newTab: NEW_TAB
    };
  }
}
