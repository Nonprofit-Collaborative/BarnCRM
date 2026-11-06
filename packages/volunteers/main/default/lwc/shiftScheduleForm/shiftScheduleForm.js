import { LightningElement, api } from 'lwc';
import Toast from 'lightning/toast';
import { CloseActionScreenEvent } from 'lightning/actions';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import LOCALE from '@salesforce/i18n/locale';
import getFormSettings from '@salesforce/apex/ShiftScheduleController.getFormSettings';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { shiftPreview } from './preview';

import NEW_TITLE from '@salesforce/label/c.Volunteers_ScheduleForm_New';
import EDIT_TITLE from '@salesforce/label/c.Volunteers_ScheduleForm_Edit';
import SAVE from '@salesforce/label/c.Core_Kit_Save';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';

const SCHEDULE_OBJECT = 'Shift_Schedule__c';
/** The fields the preview reads, by field name. */
const PATTERN_FIELDS = {
  Weekdays__c: 'weekdays',
  Every_N_Weeks__c: 'everyNWeeks',
  Start_Time__c: 'startTime',
  Start_Date__c: 'startDate',
  End_Date__c: 'endDate',
  Active__c: 'active'
};

/**
 * New Shift Schedule on a job and Edit Schedule on a shift schedule (modules-24, D-183): the
 * schedule's fields with a line under them that says how many shifts the pattern makes from today
 * through the horizon, updated as the days, the repeat and the dates change. It saves through the
 * standard record form, so every schedule rule and the save's own run apply as on New and Edit,
 * which stay.
 */
export default class ShiftScheduleForm extends LightningElement {
  @api recordId;
  @api objectApiName;

  labels = { save: SAVE, cancel: CANCEL };
  scheduleObject = SCHEDULE_OBJECT;
  pattern = { weekdays: '', everyNWeeks: 1, startDate: null, endDate: null, active: true };
  settings;
  saving = false;
  helpReady = isHelpLoaded('Volunteers');

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Volunteers').then(() => {
        this.helpReady = true;
      });
    }
    // Not cached: today and the time now are read when the form opens.
    getFormSettings()
      .then((data) => {
        this.settings = data;
      })
      .catch(() => {
        // No preview line; the form still saves.
      });
  }

  get isEdit() {
    return this.objectApiName === SCHEDULE_OBJECT;
  }

  get title() {
    return this.isEdit ? EDIT_TITLE : NEW_TITLE;
  }

  get scheduleId() {
    return this.isEdit ? this.recordId : undefined;
  }

  get jobId() {
    return this.isEdit ? undefined : this.recordId;
  }

  get previewText() {
    if (!this.settings || !this.helpReady) {
      return undefined;
    }
    if (!this.pattern.active) {
      return helpText('Volunteers', 'Volunteers_Schedule_Inactive');
    }
    const result = shiftPreview(
      this.pattern,
      this.settings.today,
      this.settings.horizonWeeks,
      this.settings.now
    );
    if (result.problem === 'weekdays') {
      return helpText('Volunteers', 'Volunteers_ScheduleForm_NoDays');
    }
    if (result.problem === 'dates') {
      return helpText('Volunteers', 'Volunteers_ScheduleForm_BadDates');
    }
    const through = formatDate(result.through);
    if (result.count === 0) {
      return helpText('Volunteers', 'Volunteers_ScheduleForm_None', through);
    }
    if (this.isEdit) {
      return result.count === 1
        ? helpText('Volunteers', 'Volunteers_ScheduleForm_HoldsOne', through)
        : helpText('Volunteers', 'Volunteers_ScheduleForm_Holds', result.count, through);
    }
    return result.count === 1
      ? helpText('Volunteers', 'Volunteers_Schedule_PreviewOne', through)
      : helpText('Volunteers', 'Volunteers_Schedule_Preview', result.count, through);
  }

  /** An edited schedule's saved values, so the preview starts from them. */
  handleLoad(event) {
    const records = event.detail && event.detail.records;
    const record = records && this.recordId ? records[this.recordId] : undefined;
    if (!this.isEdit || !record) {
      return;
    }
    const next = { ...this.pattern };
    Object.entries(PATTERN_FIELDS).forEach(([field, key]) => {
      if (record.fields[field]) {
        next[key] = record.fields[field].value;
      }
    });
    this.pattern = next;
  }

  handleFieldChange(event) {
    const key = PATTERN_FIELDS[event.target.fieldName];
    if (key) {
      const detail = event.detail || {};
      const value =
        key === 'active'
          ? detail.checked === true || detail.value === true
          : (detail.value ?? event.target.value);
      this.pattern = { ...this.pattern, [key]: value };
    }
  }

  get saveDisabled() {
    return this.saving;
  }

  handleCancel() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }

  handleSave() {
    const inputs = [...this.template.querySelectorAll('lightning-input-field')];
    const valid = inputs.reduce((ok, input) => input.reportValidity() && ok, true);
    if (!valid) {
      return;
    }
    this.saving = true;
    this.template.querySelector('lightning-record-edit-form').submit();
  }

  handleSuccess() {
    this.saving = false;
    Toast.show(
      { label: helpText('Volunteers', 'Volunteers_ScheduleForm_Saved'), variant: 'success' },
      this
    );
    if (this.recordId) {
      notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
    }
    this.dispatchEvent(new CloseActionScreenEvent());
  }

  handleError() {
    this.saving = false;
  }
}

function formatDate(isoDate) {
  if (!isoDate) {
    return '';
  }
  const [year, month, day] = isoDate.split('-').map(Number);
  return new Intl.DateTimeFormat(LOCALE, { dateStyle: 'medium', timeZone: 'UTC' }).format(
    new Date(Date.UTC(year, month - 1, day))
  );
}
