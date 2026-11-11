import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getSettingsLink from '@salesforce/apex/SettingsController.getSettingsLink';
import getState from '@salesforce/apex/ModuleManagerController.getState';
import HEADING from '@salesforce/label/c.Core_HubModules_Title';
import LINK from '@salesforce/label/c.Core_HubModules_ManagerLink';
// Every module on this card is installed, so the badge says only On or Off: "Installed and off"
// read as "Installed" at a glance (owner QA, 2026-11-05).
import STATUS_ON from '@salesforce/label/c.Core_Feature_On';
import STATUS_OFF from '@salesforce/label/c.Core_Feature_Off';
import OPEN_APP from '@salesforce/label/c.Core_ModuleManager_OpenApp';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { iconFor } from 'c/barnIcons';

const MODULES_SECTION = 'Modules';
const NOT_INSTALLED = 'NotInstalled';

// Each module app's logo, a content asset its own package ships (vis-core-12). A module with
// no app of its own shows the avatar's fallback icon.
const LOGOS = {
  Giving: 'BarnCRM_Fundraising_Logo',
  Volunteers: 'BarnCRM_Volunteers_Logo',
  Programs: 'BarnCRM_Programs_Logo',
  Funders: 'BarnCRM_Funders_Logo',
  LogicModels: 'BarnCRM_Logic_Models_Logo',
  Forms: 'BarnCRM_Forms_Logo',
  Events: 'BarnCRM_Events_Logo'
};

function logoUrl(name) {
  return LOGOS[name] ? `/file-asset/${LOGOS[name]}` : undefined;
}

// A module with no logo shows its main tab's icon, so the icon here matches the tab (D-170):
// Portal Builder its Portals tab, Contact Point Sync its page tab, Payments its Payments tab.
// Others keep the apps icon.
const FALLBACK_TABS = {
  Portal: 'Portal__c',
  ContactPoints: 'Contact_Point_Sync',
  CorporateHub: 'Corporate_Hub',
  Payments: 'Payment__c',
  LwcBuilder: 'LWC_Builder'
};
const DEFAULT_ICON = 'standard:apps';

function fallbackIcon(name) {
  return FALLBACK_TABS[name] ? iconFor(FALLBACK_TABS[name], DEFAULT_ICON) : DEFAULT_ICON;
}

/**
 * The installed BarnCRM modules and whether each is on, on the BarnCRM home page. It reads the
 * Module Manager's own list, so the two never disagree; turning a module on or off is done there.
 * A module with an app of its own links to it, so people find where the module's work is done.
 */
export default class HubModules extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded('Core');

  labels = { heading: HEADING, link: LINK, openApp: OPEN_APP };

  rows = [];
  errorMessage;

  // The Module Manager's own call is not cacheable, so it is called here rather than wired.
  async connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
    try {
      const data = await getState();
      this.rows = ((data && data.modules) || [])
        .filter((module) => module.status !== NOT_INSTALLED)
        .map((module) => ({
          name: module.name,
          displayName: module.label || module.name,
          appUrl: module.appUrl,
          logoUrl: logoUrl(module.name),
          fallbackIcon: fallbackIcon(module.name),
          statusText: module.status === 'Off' ? STATUS_OFF : STATUS_ON,
          status: module.status === 'Off' ? 'off' : 'on'
        }));
      this.errorMessage = undefined;
    } catch {
      this.errorMessage = helpText('Core', 'Core_ModuleManager_LoadErrorMessage');
    }
  }

  // The tab and the section key are qualified for the org's namespace in Apex.
  async handleOpenManager() {
    try {
      const link = await getSettingsLink();
      this[NavigationMixin.Navigate]({
        type: 'standard__navItemPage',
        attributes: { apiName: link.tabApiName },
        state: { [link.sectionKey]: MODULES_SECTION }
      });
    } catch {
      this.errorMessage = helpText('Core', 'Core_ModuleManager_LoadErrorMessage');
    }
  }
}
