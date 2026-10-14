import { LightningElement, api } from 'lwc';
import PRESENT from '@salesforce/label/c.Core_SetupAssistant_ModulePresent';
import ABSENT from '@salesforce/label/c.Core_SetupAssistant_ModuleAbsent';
import LEARN_MORE from '@salesforce/label/c.Core_SetupAssistant_ModuleLearnMore';
import MANAGER_NOTICE from '@salesforce/label/c.Core_SetupAssistant_ModuleManagerNotice';
import INSTALL from '@salesforce/label/c.Core_SuiteChoice_ModuleInstallLink';
import NEW_TAB from '@salesforce/label/c.Core_SuiteChoice_NewTab';

/**
 * The modules step: the BarnCRM packages this org is offered, by their "BarnCRM X" names
 * (ADR-NEXT), which of them are here, where to
 * read what each one does, and Salesforce's installer for a published one that is not here
 * (C-30). Turning a module on and off with one click is the Module Manager, and the notice
 * says so rather than pretending otherwise.
 */
export default class SetupStepModules extends LightningElement {
  @api modules = [];

  labels = {
    learnMore: LEARN_MORE,
    managerNotice: MANAGER_NOTICE,
    install: INSTALL,
    newTab: NEW_TAB
  };

  get rows() {
    return (this.modules || []).map((module) => ({
      ...module,
      displayName: module.label || module.name,
      status: module.present ? PRESENT : ABSENT,
      statusClass: module.present
        ? 'slds-badge slds-theme_success'
        : 'slds-badge slds-badge_inverse'
    }));
  }
}
