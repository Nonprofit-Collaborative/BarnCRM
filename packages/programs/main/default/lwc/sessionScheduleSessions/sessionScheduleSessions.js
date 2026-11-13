import { LightningElement, api, wire } from 'lwc';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { getRecord, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import LOCALE from '@salesforce/i18n/locale';
import getSchedulePreview from '@salesforce/apex/SessionScheduleController.getSchedulePreview';
import createSessionsNow from '@salesforce/apex/SessionScheduleController.createSessionsNow';
import removeFutureSessions from '@salesforce/apex/SessionScheduleController.removeFutureSessions';
import BarnConfirmModal from 'c/barnConfirmModal';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { formatDate as formatDay } from 'c/barnFormat';
import SESSION_OBJECT from '@salesforce/schema/Session__c';
import MODIFIED from '@salesforce/schema/Session_Schedule__c.LastModifiedDate';

import CREATE_NOW from '@salesforce/label/c.Programs_Schedule_CreateNow';
import REMOVE_FUTURE from '@salesforce/label/c.Programs_Schedule_RemoveFuture';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';

/**
 * The sessions panel on a session schedule (modules-24, canonical model 29ZA7), the Programs
 * twin of the shift schedule's panel: how many sessions the next run creates and through which
 * day, Create Sessions Now (R-SS3), and Remove Future Sessions after a confirm (R-SS5).
 */
export default class SessionScheduleSessions extends LightningElement {
  @api recordId;

  labels = { createNow: CREATE_NOW, removeFuture: REMOVE_FUTURE, loading: LOADING };
  preview;
  errorMessage;
  resultMessage;
  working = false;
  helpReady = isHelpLoaded('Programs');
  sessionLabel;

  @wire(getObjectInfo, { objectApiName: SESSION_OBJECT })
  wiredSessionInfo({ data }) {
    if (data) {
      this.sessionLabel = data.labelPlural;
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
      loadHelp('Programs').then(() => {
        this.helpReady = true;
      });
    }
  }

  async load() {
    try {
      this.preview = await getSchedulePreview({ scheduleId: this.recordId });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageOf(error) || helpText('Programs', 'Programs_Fail_Schedule');
    }
  }

  get isLoading() {
    return !this.preview && !this.errorMessage;
  }

  get title() {
    return this.sessionLabel || '';
  }

  get previewText() {
    const preview = this.preview;
    if (!preview || !this.helpReady) {
      return undefined;
    }
    if (preview.turnedOff) {
      return helpText('Programs', 'Programs_SessionSchedule_TurnedOff');
    }
    if (!preview.active) {
      return helpText('Programs', 'Programs_SessionSchedule_Inactive');
    }
    const through = formatDate(preview.through);
    if (preview.missing === 1) {
      return helpText('Programs', 'Programs_SessionSchedule_PreviewOne', through);
    }
    if (preview.missing > 1) {
      return helpText('Programs', 'Programs_SessionSchedule_Preview', preview.missing, through);
    }
    return helpText('Programs', 'Programs_SessionSchedule_UpToDate', through);
  }

  /** Under the preview: edits apply after the last day already created (R-SS4). */
  get editNote() {
    const preview = this.preview;
    if (!preview || !preview.createdThrough || !this.helpReady || preview.turnedOff) {
      return undefined;
    }
    return helpText(
      'Programs',
      'Programs_SessionSchedule_EditNote',
      formatDate(preview.createdThrough)
    );
  }

  get showCreate() {
    return Boolean(this.preview && this.preview.canCreate);
  }

  get createDisabled() {
    return this.working || !(this.preview && this.preview.missing > 0);
  }

  get showRemove() {
    return Boolean(this.preview && this.preview.canRemove);
  }

  async handleCreateNow() {
    await this.act(createSessionsNow, (preview) =>
      helpText('Programs', 'Programs_SessionSchedule_Created', preview.created || 0)
    );
  }

  async handleRemoveFuture() {
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: REMOVE_FUTURE,
      message: helpText('Programs', 'Programs_SessionSchedule_RemoveConfirm'),
      confirmLabel: REMOVE_FUTURE,
      cancelLabel: CANCEL,
      confirmVariant: 'destructive'
    });
    if (confirmed !== true) {
      return;
    }
    await this.act(removeFutureSessions, (preview) =>
      helpText('Programs', 'Programs_SessionSchedule_Removed', preview.removed || 0)
    );
  }

  async act(action, message) {
    this.working = true;
    this.resultMessage = undefined;
    this.errorMessage = undefined;
    try {
      this.preview = await action({ scheduleId: this.recordId });
      this.resultMessage = message(this.preview);
      notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
    } catch (error) {
      this.errorMessage = messageOf(error) || helpText('Programs', 'Programs_Fail_Schedule');
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
