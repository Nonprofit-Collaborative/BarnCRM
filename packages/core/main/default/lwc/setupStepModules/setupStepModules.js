import { LightningElement, api } from 'lwc';
import PRESENT from '@salesforce/label/c.Core_SetupAssistant_ModulePresent';
import ABSENT from '@salesforce/label/c.Core_SetupAssistant_ModuleAbsent';
import LEARN_MORE from '@salesforce/label/c.Core_SetupAssistant_ModuleLearnMore';
import MANAGER_NOTICE from '@salesforce/label/c.Core_SetupAssistant_ModuleManagerNotice';

/**
 * Step six: the six BarnCRM packages, which of them are in this org, and where to read
 * what each one does. Turning a module on and off with one click is the Module Manager, in
 * version 0.7, and the notice says so rather than pretending otherwise.
 */
export default class SetupStepModules extends LightningElement {
  @api modules = [];

  labels = {
    learnMore: LEARN_MORE,
    managerNotice: MANAGER_NOTICE
  };

  get rows() {
    return (this.modules || []).map((module) => ({
      ...module,
      status: module.present ? PRESENT : ABSENT,
      statusClass: module.present
        ? 'slds-badge slds-theme_success'
        : 'slds-badge slds-badge_inverse'
    }));
  }
}
