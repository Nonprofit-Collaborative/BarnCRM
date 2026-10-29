import { LightningElement } from 'lwc';
import hasManageSettings from '@salesforce/customPermission/Manage_BarnCRM_Settings';
import getOrganizationAddress from '@salesforce/apex/SettingsController.getOrganizationAddress';
import saveSettings from '@salesforce/apex/SettingsController.saveSettings';
import SAVE from '@salesforce/label/c.Core_OrganizationAddress_Save';
import SAVED from '@salesforce/label/c.Core_OrganizationAddress_Saved';
import FILL_REQUIRED from '@salesforce/label/c.Core_OrganizationAddress_FillRequired';
import LOAD_ERROR from '@salesforce/label/c.Core_OrganizationAddress_LoadError';
import SAVE_ERROR from '@salesforce/label/c.Core_Settings_SaveErrorMessage';
import getCompanyAddress from '@salesforce/apex/SettingsController.getCompanyAddress';
import NOT_SET from '@salesforce/label/c.Core_Settings_NotSet';
import COMPANY_SUGGESTION from '@salesforce/label/c.Core_OrganizationAddress_CompanySuggestion';
import USE_COMPANY from '@salesforce/label/c.Core_OrganizationAddress_UseCompany';

/** The address parts in the order they are printed. */
const PRINT_ORDER = [
  'Organization_Street__c',
  'Organization_Street_2__c',
  'Organization_City__c',
  'Organization_State__c',
  'Organization_Postal_Code__c',
  'Organization_Country__c'
];

/**
 * The organization address in the settings console: one grouped address block and its own Save
 * button, a Component row beside the other Organization settings. It saves through the same
 * `saveSettings` the console uses, so the server's all-or-nothing rule applies (R-OA1), and tells
 * the console what it saved so Recent changes can refresh.
 *
 * A blank part says "Not set" in its box. While no address is saved, a complete Company
 * Information address is offered: Use This Address fills the block, and Save saves it.
 */
export default class OrganizationAddressSettings extends LightningElement {
  labels = { save: SAVE, notSet: NOT_SET, useCompany: USE_COMPANY };

  values = {};
  saved = {};
  companyAddress = {};
  message;
  messageIsError = false;

  get canEdit() {
    return hasManageSettings === true;
  }

  get isReadOnly() {
    return !this.canEdit;
  }

  get isDirty() {
    return Object.keys(this.values).some((key) => this.values[key] !== this.saved[key]);
  }

  get saveDisabled() {
    return !this.canEdit || !this.isDirty;
  }

  get messageClass() {
    return this.messageIsError
      ? 'slds-text-color_error slds-var-m-top_x-small'
      : 'slds-text-color_success slds-var-m-top_x-small';
  }

  connectedCallback() {
    return this.load();
  }

  /** Offered while nothing is saved or typed, to someone who can save it. */
  get showsCompanyAddress() {
    const empty = (parts) => !Object.values(parts).some((value) => value);
    return this.canEdit && !empty(this.companyAddress) && empty(this.saved) && empty(this.values);
  }

  get companyAddressText() {
    const oneLine = PRINT_ORDER.map((key) => this.companyAddress[key])
      .filter((value) => value)
      .join(', ');
    return COMPANY_SUGGESTION.replace('{0}', oneLine);
  }

  async load() {
    try {
      const parts = (await getOrganizationAddress()) || {};
      this.saved = { ...parts };
      this.values = { ...parts };
    } catch {
      this.showError(LOAD_ERROR);
      return;
    }
    if (this.canEdit) {
      try {
        this.companyAddress = (await getCompanyAddress()) || {};
      } catch {
        // Only a suggestion: without it the block works as before.
        this.companyAddress = {};
      }
    }
  }

  /** Fills the block from Company Information; nothing is saved until Save. */
  handleUseCompanyAddress() {
    this.values = { ...this.values, ...this.companyAddress };
    this.message = undefined;
  }

  handlePartChange(event) {
    this.values = { ...this.values, [event.detail.key]: event.detail.value || '' };
    this.message = undefined;
  }

  async handleSave() {
    if (!this.canEdit || !this.isDirty) {
      return;
    }
    const block = this.template.querySelector('c-organization-address');
    if (block && block.reportValidity() === false) {
      this.showError(FILL_REQUIRED);
      return;
    }
    try {
      await saveSettings({ values: { ...this.values } });
      this.saved = { ...this.values };
      this.messageIsError = false;
      this.message = SAVED;
      this.dispatchEvent(new CustomEvent('settingssaved'));
    } catch (error) {
      this.showError((error && error.body && error.body.message) || SAVE_ERROR);
    }
  }

  showError(text) {
    this.messageIsError = true;
    this.message = text;
  }
}
