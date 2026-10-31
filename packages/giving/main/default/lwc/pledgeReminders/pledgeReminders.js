import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getPage from '@salesforce/apex/PledgeReminderController.getPage';
import sendNow from '@salesforce/apex/PledgeReminderController.sendNow';
import produceLetters from '@salesforce/apex/PledgeReminderController.produceLetters';
import markLettersSent from '@salesforce/apex/PledgeReminderController.markLettersSent';
import setSchedule from '@salesforce/apex/PledgeReminderController.setSchedule';

import TITLE from '@salesforce/label/c.Giving_PledgeReminders_Title';
import INTRO from '@salesforce/label/c.Giving_PledgeReminders_Intro';
import OFF from '@salesforce/label/c.Giving_PledgeReminders_Off';
import NO_STEPS from '@salesforce/label/c.Giving_PledgeReminders_NoSteps';
import QUEUE_HEADING from '@salesforce/label/c.Giving_PledgeReminders_QueueHeading';
import EMAILS_DUE from '@salesforce/label/c.Giving_PledgeReminders_EmailsDue';
import LETTERS_DUE from '@salesforce/label/c.Giving_PledgeReminders_LettersDue';
import WITHOUT_RECIPIENT from '@salesforce/label/c.Giving_PledgeReminders_WithoutRecipient';
import LETTERS_WAITING from '@salesforce/label/c.Giving_PledgeReminders_LettersWaiting';
import LETTERS_AWAITING from '@salesforce/label/c.Giving_PledgeReminders_LettersAwaiting';
import SEND_NOW from '@salesforce/label/c.Giving_PledgeReminders_SendNow';
import SEND_STARTED from '@salesforce/label/c.Giving_PledgeReminders_SendStarted';
import PRODUCE_LETTERS from '@salesforce/label/c.Giving_PledgeReminders_ProduceLetters';
import LETTERS_READY from '@salesforce/label/c.Giving_PledgeReminders_LettersReady';
import MARK_SENT from '@salesforce/label/c.Giving_PledgeReminders_MarkSent';
import LETTERS_MARKED_SENT from '@salesforce/label/c.Giving_PledgeReminders_LettersMarkedSent';
import NIGHTLY from '@salesforce/label/c.Giving_PledgeReminders_Nightly';
import NEXT_RUN from '@salesforce/label/c.Giving_PledgeReminders_NextRun';
import NOT_SCHEDULED from '@salesforce/label/c.Giving_PledgeReminders_NotScheduled';
import LAST_RUN from '@salesforce/label/c.Giving_PledgeReminders_LastRun';
import NEVER_RUN from '@salesforce/label/c.Giving_PledgeReminders_NeverRun';
import STEPS_HEADING from '@salesforce/label/c.Giving_PledgeReminders_StepsHeading';
import NEW_STEP from '@salesforce/label/c.Giving_PledgeReminders_NewStep';
import EDIT_STEP from '@salesforce/label/c.Giving_PledgeReminders_EditStep';
import EDIT_STEP_OF from '@salesforce/label/c.Giving_PledgeReminders_EditStepOf';
import NEW_STEP_HEADING from '@salesforce/label/c.Giving_PledgeReminders_NewStepHeading';
import EDIT_STEP_HEADING from '@salesforce/label/c.Giving_PledgeReminders_EditStepHeading';
import TEMPLATE_FIELD from '@salesforce/label/c.Giving_PledgeReminders_TemplateField';
import TEMPLATE_FIELD_HELP from '@salesforce/label/c.Giving_PledgeReminders_TemplateFieldHelp';
import TEMPLATE_PLACEHOLDER from '@salesforce/label/c.Giving_PledgeReminders_TemplatePlaceholder';
import TEMPLATE_REQUIRED from '@salesforce/label/c.Giving_PledgeReminders_TemplateRequired';
import SAVE_STEP from '@salesforce/label/c.Giving_PledgeReminders_SaveStep';
import CANCEL_STEP from '@salesforce/label/c.Giving_PledgeReminders_CancelStep';
import STEP_SAVED from '@salesforce/label/c.Giving_PledgeReminders_StepSaved';
import LOG_HEADING from '@salesforce/label/c.Giving_PledgeReminders_LogHeading';
import NO_LOG from '@salesforce/label/c.Giving_PledgeReminders_NoLog';
import TEMPLATE_MISSING from '@salesforce/label/c.Giving_PledgeReminders_TemplateMissing';
import INACTIVE from '@salesforce/label/c.Giving_PledgeReminders_Inactive';
import ACTION_FAILED from '@salesforce/label/c.Giving_PledgeReminders_ActionFailed';
import COLUMN_STEP from '@salesforce/label/c.Giving_PledgeReminders_ColumnStep';
import COLUMN_TIMING from '@salesforce/label/c.Giving_PledgeReminders_ColumnTiming';
import COLUMN_CHANNEL from '@salesforce/label/c.Giving_PledgeReminders_ColumnChannel';
import COLUMN_TEMPLATE from '@salesforce/label/c.Giving_PledgeReminders_ColumnTemplate';
import COLUMN_PLEDGE from '@salesforce/label/c.Giving_PledgeReminders_ColumnPledge';
import COLUMN_INSTALLMENT from '@salesforce/label/c.Giving_PledgeReminders_ColumnInstallment';
import COLUMN_STATUS from '@salesforce/label/c.Giving_PledgeReminders_ColumnStatus';
import COLUMN_SENT_ON from '@salesforce/label/c.Giving_PledgeReminders_ColumnSentOn';
import DOWNLOAD_FILE from '@salesforce/label/c.Giving_PledgeReminders_DownloadFile';
import DAYS_BEFORE from '@salesforce/label/c.Giving_PledgeReminders_DaysBefore';
import ON_DUE_DATE from '@salesforce/label/c.Giving_PledgeReminders_OnDueDate';
import DAYS_AFTER from '@salesforce/label/c.Giving_PledgeReminders_DaysAfter';

const FILE_DOWNLOAD_PATH = '/sfc/servlet.shepherd/document/download/';
const CHANNEL_EMAIL = 'Email';

/**
 * Pledge reminders, as the person running fundraising reads them: the steps of the ladder, what
 * is due to go on the next run, the buttons that send it, and the log.
 *
 * A step is created and edited here, in a standard record edit form, for the reason the
 * Acknowledgments page does it for rules: a step names its email template by developer name,
 * so the template is a picker built from the templates the page already lists.
 *
 * Whether reminders are on at all is a setting in BarnCRM Settings, under Giving, and this page
 * says so when it is off rather than offering a second switch.
 */
export default class PledgeReminders extends NavigationMixin(LightningElement) {
  labels = {
    title: TITLE,
    intro: INTRO,
    off: OFF,
    noSteps: NO_STEPS,
    queueHeading: QUEUE_HEADING,
    emailsDue: EMAILS_DUE,
    lettersDue: LETTERS_DUE,
    withoutRecipient: WITHOUT_RECIPIENT,
    lettersWaiting: LETTERS_WAITING,
    lettersAwaiting: LETTERS_AWAITING,
    sendNow: SEND_NOW,
    produceLetters: PRODUCE_LETTERS,
    markSent: MARK_SENT,
    nightly: NIGHTLY,
    nextRun: NEXT_RUN,
    lastRun: LAST_RUN,
    stepsHeading: STEPS_HEADING,
    newStep: NEW_STEP,
    editStep: EDIT_STEP,
    templateField: TEMPLATE_FIELD,
    templateFieldHelp: TEMPLATE_FIELD_HELP,
    templatePlaceholder: TEMPLATE_PLACEHOLDER,
    templateRequired: TEMPLATE_REQUIRED,
    saveStep: SAVE_STEP,
    cancelStep: CANCEL_STEP,
    logHeading: LOG_HEADING,
    noLog: NO_LOG,
    inactive: INACTIVE,
    columnStep: COLUMN_STEP,
    columnTiming: COLUMN_TIMING,
    columnChannel: COLUMN_CHANNEL,
    columnTemplate: COLUMN_TEMPLATE,
    columnPledge: COLUMN_PLEDGE,
    columnInstallment: COLUMN_INSTALLMENT,
    columnStatus: COLUMN_STATUS,
    columnSentOn: COLUMN_SENT_ON,
    downloadFile: DOWNLOAD_FILE
  };

  page;
  wiredPage;
  errorMessage;
  noticeMessage;
  busy = false;

  /** The step form: closed, open on a new step (undefined id), or open on an existing one. */
  showStepForm = false;
  editingStepId;
  stepChannel;
  stepTemplate;

  @wire(getPage)
  wiredResult(result) {
    this.wiredPage = result;
    if (result.data) {
      this.page = result.data;
      this.errorMessage = undefined;
    }
    if (result.error) {
      this.errorMessage = this.messageFrom(result.error);
    }
  }

  get hasPage() {
    return !!this.page;
  }

  get showOffNotice() {
    return !!this.page && this.page.enabled === false;
  }

  get hasSteps() {
    return !!(this.page && this.page.steps && this.page.steps.length);
  }

  get showNoSteps() {
    return !!this.page && !this.hasSteps;
  }

  get hasReminders() {
    return !!(this.page && this.page.reminders && this.page.reminders.length);
  }

  get showNoReminders() {
    return !!this.page && !this.hasReminders;
  }

  get canManage() {
    return !!this.page && this.page.canManage === true;
  }

  get templateOptions() {
    const templates = (this.page && this.page.templates) || [];
    return templates.map((template) => ({
      label: template.label,
      value: template.developerName
    }));
  }

  get stepIsEmail() {
    return this.stepChannel === CHANNEL_EMAIL;
  }

  get stepFormHeading() {
    return this.editingStepId ? EDIT_STEP_HEADING : NEW_STEP_HEADING;
  }

  get scheduled() {
    return !!this.page && this.page.scheduled === true;
  }

  get nextRunText() {
    if (!this.page || !this.page.nextRunAt) {
      return NOT_SCHEDULED;
    }
    return new Date(this.page.nextRunAt).toLocaleString();
  }

  get lastRunText() {
    if (!this.page || !this.page.lastRun) {
      return NEVER_RUN;
    }
    const when = new Date(this.page.lastRun).toLocaleString();
    return this.page.lastRunSummary ? `${when}: ${this.page.lastRunSummary}` : when;
  }

  get hasLettersFile() {
    return !!(this.page && this.page.lettersFileId);
  }

  get lettersFileUrl() {
    return this.hasLettersFile ? FILE_DOWNLOAD_PATH + this.page.lettersFileId : '';
  }

  get hasLettersAwaiting() {
    return !!this.page && this.page.lettersAwaitingConfirmation > 0;
  }

  /** The steps with the two things a raw record cannot say: when, and whether the template exists. */
  get steps() {
    if (!this.hasSteps) {
      return [];
    }
    return this.page.steps.map((step) => ({
      ...step,
      timingText: this.timing(step.days),
      templateText:
        step.channel !== CHANNEL_EMAIL
          ? ''
          : step.templateFound
            ? step.templateLabel
            : TEMPLATE_MISSING,
      templateMissing: step.channel === CHANNEL_EMAIL && step.templateFound === false,
      activeText: step.active ? '' : INACTIVE,
      editTitle: EDIT_STEP_OF.replace('{0}', step.name)
    }));
  }

  get reminders() {
    if (!this.hasReminders) {
      return [];
    }
    return this.page.reminders.map((reminder) => ({
      ...reminder,
      sentOnText: reminder.sentOn ? new Date(reminder.sentOn).toLocaleString() : '',
      hasFile: !!reminder.fileId,
      fileUrl: reminder.fileId ? FILE_DOWNLOAD_PATH + reminder.fileId : ''
    }));
  }

  get sendDisabled() {
    return (
      this.busy ||
      !this.page ||
      this.page.enabled !== true ||
      this.page.canSend !== true ||
      !(this.page.emailsDue + this.page.lettersDue > 0)
    );
  }

  get lettersDisabled() {
    return this.busy || !this.page || this.page.canSend !== true || !this.page.lettersWaiting;
  }

  get markSentDisabled() {
    return this.busy || !this.page || this.page.canSend !== true || !this.hasLettersAwaiting;
  }

  get scheduleDisabled() {
    return this.busy || !this.page || this.page.canManage !== true;
  }

  get hasError() {
    return !!this.errorMessage;
  }

  get hasNotice() {
    return !!this.noticeMessage;
  }

  timing(days) {
    if (days === null || days === undefined) {
      return '';
    }
    if (days < 0) {
      return DAYS_BEFORE.replace('{0}', String(-days));
    }
    if (days === 0) {
      return ON_DUE_DATE;
    }
    return DAYS_AFTER.replace('{0}', String(days));
  }

  handleNewStep() {
    this.openStepForm(undefined);
  }

  handleEditStep(event) {
    this.openStepForm(event.currentTarget.dataset.recordId);
  }

  openStepForm(stepId) {
    const step = stepId ? this.page.steps.find((row) => row.id === stepId) : undefined;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    this.editingStepId = stepId;
    // A new step starts on Email, the field's default, so the picker shows from the start.
    this.stepChannel = step ? step.channel : CHANNEL_EMAIL;
    this.stepTemplate = step ? step.template : undefined;
    this.showStepForm = true;
  }

  handleChannelChange(event) {
    this.stepChannel = event.detail.value;
  }

  handleStepTemplateChange(event) {
    this.stepTemplate = event.detail.value;
  }

  handleCancelStep() {
    this.showStepForm = false;
  }

  handleStepSubmit(event) {
    event.preventDefault();
    const fields = { ...event.detail.fields };
    if (this.stepIsEmail && !this.stepTemplate) {
      this.template.querySelector('[data-id="step-template"]').reportValidity();
      return;
    }
    fields.Email_Template__c = this.stepIsEmail ? this.stepTemplate : null;
    this.template.querySelector('lightning-record-edit-form').submit(fields);
  }

  handleStepSaved() {
    this.showStepForm = false;
    this.noticeMessage = STEP_SAVED;
    return refreshApex(this.wiredPage);
  }

  handleOpenStep(event) {
    this[NavigationMixin.Navigate]({
      type: 'standard__recordPage',
      attributes: {
        recordId: event.currentTarget.dataset.recordId,
        objectApiName: 'Pledge_Reminder_Step__c',
        actionName: 'view'
      }
    });
  }

  handleSendNow() {
    return this.run(sendNow(), SEND_STARTED);
  }

  handleProduceLetters() {
    return this.run(produceLetters(), LETTERS_READY);
  }

  handleMarkSent() {
    return this.run(markLettersSent(), LETTERS_MARKED_SENT);
  }

  handleScheduleChange(event) {
    return this.run(setSchedule({ scheduled: event.target.checked }), undefined);
  }

  /** Every action is the same three steps, so they are written once. */
  run(promise, notice) {
    this.busy = true;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    return promise
      .then((view) => {
        this.page = view;
        this.noticeMessage = notice;
        return refreshApex(this.wiredPage);
      })
      .catch((error) => {
        this.errorMessage = this.messageFrom(error);
      })
      .finally(() => {
        this.busy = false;
      });
  }

  messageFrom(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    return ACTION_FAILED;
  }
}
