import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getSettingsLink from '@salesforce/apex/SettingsController.getSettingsLink';
import getState from '@salesforce/apex/ModuleManagerController.getState';
import HEADING from '@salesforce/label/c.Core_HubModules_Title';
import LINK from '@salesforce/label/c.Core_HubModules_ManagerLink';
import STATUS_ON from '@salesforce/label/c.Core_ModuleManager_StatusOn';
import STATUS_OFF from '@salesforce/label/c.Core_ModuleManager_StatusOff';
import LOAD_ERROR from '@salesforce/label/c.Core_ModuleManager_LoadErrorMessage';
import OPEN_APP from '@salesforce/label/c.Core_ModuleManager_OpenApp';

const MODULES_SECTION = 'Modules';
const NOT_INSTALLED = 'NotInstalled';

/**
 * The installed BarnCRM modules and whether each is on, on the BarnCRM home page. It reads the
 * Module Manager's own list, so the two never disagree; turning a module on or off is done there.
 * A module with an app of its own links to it, so people find where the module's work is done.
 */
export default class HubModules extends NavigationMixin(LightningElement) {
  labels = { heading: HEADING, link: LINK, openApp: OPEN_APP };

  rows = [];
  errorMessage;

  // The Module Manager's own call is not cacheable, so it is called here rather than wired.
  async connectedCallback() {
    try {
      const data = await getState();
      this.rows = ((data && data.modules) || [])
        .filter((module) => module.status !== NOT_INSTALLED)
        .map((module) => ({
          name: module.name,
          displayName: module.label || module.name,
          appUrl: module.appUrl,
          statusText: module.status === 'Off' ? STATUS_OFF : STATUS_ON,
          badgeClass:
            module.status === 'Off'
              ? 'slds-badge slds-var-m-left_x-small'
              : 'slds-badge slds-theme_success slds-var-m-left_x-small'
        }));
      this.errorMessage = undefined;
    } catch {
      this.errorMessage = LOAD_ERROR;
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
      this.errorMessage = LOAD_ERROR;
    }
  }
}
