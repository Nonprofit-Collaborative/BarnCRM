import { LightningElement, api, wire } from 'lwc';
import Toast from 'lightning/toast';
import { CloseActionScreenEvent } from 'lightning/actions';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getContext from '@salesforce/apex/VolunteerLogHoursController.getContext';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

import TITLE from '@salesforce/label/c.Volunteers_LogHours_Title';
import PERSON from '@salesforce/label/c.Core_Section_Person';
import SAVE from '@salesforce/label/c.Core_Kit_Save';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';

import HOURS from '@salesforce/schema/Volunteer_Hours__c';
import HOURS_JOB from '@salesforce/schema/Volunteer_Hours__c.Volunteer_Job__c';
import HOURS_SHIFT from '@salesforce/schema/Volunteer_Hours__c.Volunteer_Shift__c';
import HOURS_DATE from '@salesforce/schema/Volunteer_Hours__c.Date_Worked__c';
import HOURS_HOURS from '@salesforce/schema/Volunteer_Hours__c.Hours__c';
import HOURS_NOTES from '@salesforce/schema/Volunteer_Hours__c.Notes__c';
import HOURS_ACCOUNT from '@salesforce/schema/Volunteer_Hours__c.Account__c';
import HOURS_CONTACT from '@salesforce/schema/Volunteer_Hours__c.Contact__c';

/** The person a tab was opened for: `c__personId` (or the namespaced key) in the page state. */
export function personIdFromState(pageRef) {
  const state = (pageRef && pageRef.state) || {};
  const key = Object.keys(state).find((name) => name.endsWith('__personId'));
  return key ? state[key] : undefined;
}

/**
 * Log Hours (modules-14): a small hours form on a person, a shift or a job, with one Person
 * picker and the values the record gives prefilled. It saves through the standard record form,
 * so every hours rule and the approval status apply as on New, which stays.
 *
 * The same form is the Log Hours tab (D-200 R1, R7): opened with `c__personId` from the
 * Volunteering at a Glance card it starts on that person, and after a save returns to them;
 * opened from Home it starts empty and clears itself for the next entry.
 */
export default class VolunteerLogHours extends NavigationMixin(LightningElement) {
  labels = { title: TITLE, person: PERSON, save: SAVE, cancel: CANCEL, loading: LOADING };
  hoursObject = HOURS.objectApiName;
  /** The form's fields, from schema imports so they carry any namespace. */
  hoursFields = {
    job: HOURS_JOB.fieldApiName,
    shift: HOURS_SHIFT.fieldApiName,
    dateWorked: HOURS_DATE.fieldApiName,
    hours: HOURS_HOURS.fieldApiName,
    notes: HOURS_NOTES.fieldApiName
  };

  context;
  personId;
  loadFailed = false;
  saving = false;
  helpReady = isHelpLoaded('Volunteers');
  _recordId;
  /** The person named in the tab's page state, when the form is the Log Hours tab. */
  statePersonId;
  /** Only the latest load applies, whichever of the record and the page state comes last. */
  loadCount = 0;

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

  @wire(CurrentPageReference)
  readPageState(pageRef) {
    const personId = personIdFromState(pageRef);
    if (!this._recordId && personId && personId !== this.statePersonId) {
      this.statePersonId = personId;
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
    const count = ++this.loadCount;
    this.loadFailed = false;
    try {
      const context = await getContext({ recordId: this._recordId || this.statePersonId || null });
      if (count === this.loadCount) {
        this.context = context;
        this.personId = context.personId;
      }
    } catch {
      if (count === this.loadCount) {
        this.loadFailed = true;
      }
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
    return (this.context && this.context.personObject === 'Account' ? HOURS_ACCOUNT : HOURS_CONTACT)
      .fieldApiName;
  }

  /** On the tab rather than in an action window. */
  get onTab() {
    return !this._recordId;
  }

  handlePersonChange(event) {
    this.personId = event.detail.recordId;
  }

  handleCancel() {
    if (this.onTab) {
      this.leaveTab();
      return;
    }
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
    const touched = this._recordId || this.statePersonId;
    if (touched) {
      notifyRecordUpdateAvailable([{ recordId: touched }]);
    }
    if (this.onTab) {
      this.leaveTab();
      return;
    }
    this.dispatchEvent(new CloseActionScreenEvent());
  }

  /** Back to the person the tab was opened for, or a fresh form for the next entry. */
  leaveTab() {
    if (this.statePersonId) {
      this[NavigationMixin.Navigate]({
        type: 'standard__recordPage',
        attributes: { recordId: this.statePersonId, actionName: 'view' }
      });
      return;
    }
    this.context = undefined;
    this.load();
  }

  handleError() {
    this.saving = false;
  }
}
