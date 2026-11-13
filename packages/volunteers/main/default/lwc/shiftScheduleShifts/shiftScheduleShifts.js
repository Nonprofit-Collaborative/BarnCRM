import { LightningElement, api, wire } from 'lwc';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { getRecord, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import LOCALE from '@salesforce/i18n/locale';
import getPreview from '@salesforce/apex/ShiftScheduleController.getPreview';
import createNow from '@salesforce/apex/ShiftScheduleController.createNow';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { formatDate as formatDay } from 'c/barnFormat';
import SHIFT_OBJECT from '@salesforce/schema/Volunteer_Shift__c';
import MODIFIED from '@salesforce/schema/Shift_Schedule__c.LastModifiedDate';

import CREATE_NOW from '@salesforce/label/c.Volunteers_Schedule_CreateNow';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';

/**
 * The shifts panel on a shift schedule (modules-15, modules-24): how many shifts the next run
 * creates and through which day, and Create Shifts Now, which runs the same shift creation as
 * the nightly job for this schedule at once.
 */
export default class ShiftScheduleShifts extends LightningElement {
  @api recordId;

  labels = { createNow: CREATE_NOW, loading: LOADING };
  preview;
  errorMessage;
  resultMessage;
  working = false;
  helpReady = isHelpLoaded('Volunteers');
  shiftLabel;

  @wire(getObjectInfo, { objectApiName: SHIFT_OBJECT })
  wiredShiftInfo({ data }) {
    if (data) {
      this.shiftLabel = data.labelPlural;
    }
  }

  /** Reloads the preview whenever the schedule is saved, here or in the details. */
  @wire(getRecord, { recordId: '$recordId', fields: [MODIFIED] })
  wiredSchedule({ data }) {
    if (data) {
      this.load();
    }
  }

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Volunteers').then(() => {
        this.helpReady = true;
      });
    }
  }

  async load() {
    try {
      this.preview = await getPreview({ scheduleId: this.recordId });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage =
        messageOf(error) || helpText('Volunteers', 'Volunteers_Schedule_LoadFailed');
    }
  }

  get isLoading() {
    return !this.preview && !this.errorMessage;
  }

  get title() {
    return this.shiftLabel || '';
  }

  get previewText() {
    const preview = this.preview;
    if (!preview || !this.helpReady) {
      return undefined;
    }
    if (preview.turnedOff) {
      return helpText('Volunteers', 'Volunteers_Schedule_TurnedOff');
    }
    if (!preview.active) {
      return helpText('Volunteers', 'Volunteers_Schedule_Inactive');
    }
    const through = formatDate(preview.through);
    if (preview.missing === 1) {
      return helpText('Volunteers', 'Volunteers_Schedule_PreviewOne', through);
    }
    if (preview.missing > 1) {
      return helpText('Volunteers', 'Volunteers_Schedule_Preview', preview.missing, through);
    }
    return helpText('Volunteers', 'Volunteers_Schedule_UpToDate', through);
  }

  get showButton() {
    return Boolean(this.preview && this.preview.canCreate);
  }

  get buttonDisabled() {
    return this.working || !this.preview || !(this.preview.missing > 0);
  }

  async handleCreateNow() {
    const before = this.preview ? this.preview.missing : 0;
    this.working = true;
    this.resultMessage = undefined;
    this.errorMessage = undefined;
    try {
      this.preview = await createNow({ scheduleId: this.recordId });
      const created = Math.max(before - this.preview.missing, 0);
      this.resultMessage = helpText('Volunteers', 'Volunteers_Schedule_Created', created);
      notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
    } catch (error) {
      this.errorMessage =
        messageOf(error) || helpText('Volunteers', 'Volunteers_Schedule_CreateFailed');
    } finally {
      this.working = false;
    }
  }
}

function messageOf(error) {
  return error && error.body && error.body.message ? error.body.message : undefined;
}

function formatDate(isoDate) {
  return formatDay(isoDate, LOCALE) || '';
}
