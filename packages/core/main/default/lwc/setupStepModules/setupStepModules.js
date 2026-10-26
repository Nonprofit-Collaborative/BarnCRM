import { LightningElement, api } from 'lwc';
import PRESENT from '@salesforce/label/c.Core_SetupAssistant_ModulePresent';
import ABSENT from '@salesforce/label/c.Core_SetupAssistant_ModuleAbsent';
import LEARN_MORE from '@salesforce/label/c.Core_SetupAssistant_ModuleLearnMore';
import MANAGER_NOTICE from '@salesforce/label/c.Core_SetupAssistant_ModuleManagerNotice';
import INSTALL from '@salesforce/label/c.Core_SuiteChoice_ModuleInstallLink';
import NEW_TAB from '@salesforce/label/c.Core_SuiteChoice_NewTab';
import INSTALL_FIRST from '@salesforce/label/c.Core_ModuleManager_InstallFirst';
import STAFF_TABS from '@salesforce/label/c.Core_SetupAssistant_ModuleStaffTabs';
import ADMIN_TABS from '@salesforce/label/c.Core_SetupAssistant_ModuleAdminTabs';
import TABS_HOW from '@salesforce/label/c.Core_SetupAssistant_ModuleTabsHow';

/**
 * The modules step: the BarnCRM packages this org is offered, by their "BarnCRM X" names
 * (ADR-0124), which of them are here, where to
 * read what each one does, and Salesforce's installer for a published one that is not here
 * (C-30). Turning a module on and off with one click is the Module Manager, and the notice
 * says so rather than pretending otherwise. An installed module's pages that belong in the
 * BarnCRM apps are listed with how to add them in App Manager, since Core's apps cannot name
 * a module's tab (ADR-0136).
 */
export default class SetupStepModules extends LightningElement {
  @api modules = [];

  labels = {
    learnMore: LEARN_MORE,
    managerNotice: MANAGER_NOTICE,
    install: INSTALL,
    newTab: NEW_TAB,
    tabsHow: TABS_HOW
  };

  get hasTabsToAdd() {
    return (this.modules || []).some(
      (module) => module.present && (module.staffTabs || module.adminTabs)
    );
  }

  get rows() {
    return (this.modules || []).map((module) => ({
      ...module,
      displayName: module.label || module.name,
      status: module.present ? PRESENT : ABSENT,
      installFirstText:
        !module.present && module.installFirst
          ? INSTALL_FIRST.replace('{0}', module.installFirst)
          : null,
      staffTabsText:
        module.present && module.staffTabs ? STAFF_TABS.replace('{0}', module.staffTabs) : null,
      adminTabsText:
        module.present && module.adminTabs ? ADMIN_TABS.replace('{0}', module.adminTabs) : null,
      statusClass: module.present
        ? 'slds-badge slds-theme_success'
        : 'slds-badge slds-badge_inverse'
    }));
  }
}
