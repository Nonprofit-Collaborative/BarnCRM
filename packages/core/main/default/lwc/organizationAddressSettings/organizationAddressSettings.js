import { LightningElement } from 'lwc';
import hasManageSettings from '@salesforce/customPermission/Manage_BarnCRM_Settings';
import getOrganizationAddress from '@salesforce/apex/SettingsController.getOrganizationAddress';
import saveSettings from '@salesforce/apex/SettingsController.saveSettings';
import SAVE from '@salesforce/label/c.Core_OrganizationAddress_Save';
import SAVED from '@salesforce/label/c.Core_OrganizationAddress_Saved';
import FILL_REQUIRED from '@salesforce/label/c.Core_OrganizationAddress_FillRequired';
import LOAD_ERROR from '@salesforce/label/c.Core_OrganizationAddress_LoadError';
import SAVE_ERROR from '@salesforce/label/c.Core_Settings_SaveErrorMessage';

/**
 * The organization address in the settings console: one grouped address block and its own Save
 * button, a Component row beside the other Organization settings. It saves through the same
 * `saveSettings` the console uses, so the server's all-or-nothing rule applies (R-OA1), and tells
 * the console what it saved so Recent changes can refresh.
 */
export default class OrganizationAddressSettings extends LightningElement {
  labels = { save: SAVE };

  values = {};
  saved = {};
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

  async load() {
    try {
      const parts = (await getOrganizationAddress()) || {};
      this.saved = { ...parts };
      this.values = { ...parts };
    } catch {
      this.showError(LOAD_ERROR);
    }
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
