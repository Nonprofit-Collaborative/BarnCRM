import { LightningElement, api } from 'lwc';
import Toast from 'lightning/toast';
import { CloseActionScreenEvent } from 'lightning/actions';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getContext from '@salesforce/apex/VolunteerLogHoursController.getContext';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

import TITLE from '@salesforce/label/c.Volunteers_LogHours_Title';
import PERSON from '@salesforce/label/c.Core_Section_Person';
import SAVE from '@salesforce/label/c.Core_Kit_Save';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';

const HOURS_OBJECT = 'Volunteer_Hours__c';

/**
 * Log Hours (modules-14): a small hours form on a person, a shift or a job, with one Person
 * picker and the values the record gives prefilled. It saves through the standard record form,
 * so every hours rule and the approval status apply as on New, which stays.
 */
export default class VolunteerLogHours extends LightningElement {
  labels = { title: TITLE, person: PERSON, save: SAVE, cancel: CANCEL, loading: LOADING };
  hoursObject = HOURS_OBJECT;

  context;
  personId;
  loadFailed = false;
  saving = false;
  helpReady = isHelpLoaded('Volunteers');
  _recordId;

  @api
  get recordId() {
    return this._recordId;
  }
  set recordId(value) {
    const changed = value !== this._recordId;
    this._recordId = value;
    if (changed) {
      this.load();
    }
  }

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Volunteers').then(() => {
        this.helpReady = true;
      });
    }
    if (!this.context && !this._recordId) {
      this.load();
    }
  }

  async load() {
    this.loadFailed = false;
    try {
      this.context = await getContext({ recordId: this._recordId });
      this.personId = this.context.personId;
    } catch {
      this.loadFailed = true;
    }
  }

  get isLoading() {
    return !this.context && !this.loadFailed;
  }

  get blocker() {
    if (this.loadFailed) {
      return helpText('Volunteers', 'Volunteers_LogHours_LoadFailed');
    }
    if (this.context && !this.context.canCreate) {
      return helpText('Volunteers', 'Volunteers_LogHours_NoAccess');
    }
    return undefined;
  }

  get showForm() {
    return Boolean(this.context) && !this.blocker;
  }

  get saveDisabled() {
    return !this.showForm || this.saving;
  }

  get personFilter() {
    if (!this.context || !this.context.personFilterField) {
      return undefined;
    }
    return {
      criteria: [{ fieldPath: this.context.personFilterField, operator: 'eq', value: true }]
    };
  }

  get personField() {
    return this.context && this.context.personObject === 'Account' ? 'Account__c' : 'Contact__c';
  }

  handlePersonChange(event) {
    this.personId = event.detail.recordId;
  }

  handleCancel() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }

  handleSave() {
    const picker = this.template.querySelector('[data-id="person-picker"]');
    const inputs = [...this.template.querySelectorAll('lightning-input-field')];
    const pickerValid = picker ? picker.reportValidity() : true;
    const inputsValid = inputs.reduce((valid, input) => input.reportValidity() && valid, true);
    if (!pickerValid || !inputsValid) {
      return;
    }
    const fields = {};
    inputs.forEach((input) => {
      fields[input.fieldName] = input.value;
    });
    fields[this.personField] = this.personId;
    this.saving = true;
    this.template.querySelector('lightning-record-edit-form').submit(fields);
  }

  handleSuccess() {
    this.saving = false;
    Toast.show(
      { label: helpText('Volunteers', 'Volunteers_LogHours_Saved'), variant: 'success' },
      this
    );
    if (this._recordId) {
      notifyRecordUpdateAvailable([{ recordId: this._recordId }]);
    }
    this.dispatchEvent(new CloseActionScreenEvent());
  }

  handleError() {
    this.saving = false;
  }
}
