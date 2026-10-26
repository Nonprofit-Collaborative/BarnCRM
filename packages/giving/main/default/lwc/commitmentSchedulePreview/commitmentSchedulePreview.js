import { LightningElement, api } from 'lwc';
import getSchedule from '@salesforce/apex/CommitmentController.getSchedule';
import generateNow from '@salesforce/apex/CommitmentController.generateNow';
import changeStatus from '@salesforce/apex/CommitmentController.changeStatus';

import TITLE from '@salesforce/label/c.Giving_SchedulePreview_Title';
import EMPTY from '@salesforce/label/c.Giving_SchedulePreview_Empty';
import GENERATE_NOW from '@salesforce/label/c.Giving_SchedulePreview_GenerateNow';
import GENERATED from '@salesforce/label/c.Giving_SchedulePreview_Generated';
import GENERATE_ERROR from '@salesforce/label/c.Giving_SchedulePreview_GenerateError';
import LOAD_ERROR from '@salesforce/label/c.Giving_SchedulePreview_LoadError';
import COLUMN_SEQUENCE from '@salesforce/label/c.Giving_SchedulePreview_ColumnSequence';
import COLUMN_DUE_DATE from '@salesforce/label/c.Giving_SchedulePreview_ColumnDueDate';
import COLUMN_AMOUNT from '@salesforce/label/c.Giving_SchedulePreview_ColumnAmount';
import COLUMN_PAID from '@salesforce/label/c.Giving_SchedulePreview_ColumnPaid';
import COLUMN_STATUS from '@salesforce/label/c.Giving_SchedulePreview_ColumnStatus';
import TOTAL from '@salesforce/label/c.Giving_SchedulePreview_Total';
import ACTION_PAUSE from '@salesforce/label/c.Giving_Commitment_ActionPause';
import ACTION_RESUME from '@salesforce/label/c.Giving_Commitment_ActionResume';
import ACTION_CANCEL from '@salesforce/label/c.Giving_Commitment_ActionCancel';
import ACTION_COMPLETE from '@salesforce/label/c.Giving_Commitment_ActionComplete';
import STATUS_CHANGED from '@salesforce/label/c.Giving_Commitment_StatusChanged';

const BADGE_BY_STATUS = {
  Paid: 'slds-theme_success',
  'Partially paid': 'slds-theme_warning',
  Overdue: 'slds-theme_error',
  Skipped: 'slds-theme_shade'
};

/**
 * The payment schedule of a commitment, shown on the commitment record page: what is due,
 * when, what has been paid, and where each payment stands. When a commitment has no
 * schedule yet, it offers to generate one.
 */
export default class CommitmentSchedulePreview extends LightningElement {
  @api recordId;

  installments = [];
  expectedTotal;
  commitmentStatus;
  loading = true;
  errorMessage;
  noticeMessage;

  labels = {
    title: TITLE,
    empty: EMPTY,
    generateNow: GENERATE_NOW,
    sequence: COLUMN_SEQUENCE,
    dueDate: COLUMN_DUE_DATE,
    amount: COLUMN_AMOUNT,
    paid: COLUMN_PAID,
    status: COLUMN_STATUS,
    total: TOTAL,
    pause: ACTION_PAUSE,
    resume: ACTION_RESUME,
    cancel: ACTION_CANCEL,
    complete: ACTION_COMPLETE
  };

  connectedCallback() {
    this.load();
  }

  get hasInstallments() {
    return this.installments.length > 0;
  }

  get isEmpty() {
    return !this.loading && !this.errorMessage && this.installments.length === 0;
  }

  /** Pause is offered on an active commitment, resume on a paused one, never both. */
  get canPause() {
    return this.commitmentStatus === 'Active';
  }

  get canResume() {
    return this.commitmentStatus === 'Paused';
  }

  /** Cancelling and completing both end a commitment, so neither is offered on an ended one. */
  get canEnd() {
    return this.commitmentStatus === 'Active' || this.commitmentStatus === 'Paused';
  }

  get hasActions() {
    return this.canPause || this.canResume || this.canEnd;
  }

  async load() {
    this.loading = true;
    this.errorMessage = undefined;
    try {
      this.absorb(await getSchedule({ commitmentId: this.recordId }));
    } catch (error) {
      this.installments = [];
      this.errorMessage = this.messageFrom(error, LOAD_ERROR);
    } finally {
      this.loading = false;
    }
  }

  async handleGenerate() {
    this.loading = true;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    try {
      this.absorb(await generateNow({ commitmentId: this.recordId }));
      this.noticeMessage = GENERATED;
    } catch (error) {
      this.errorMessage = this.messageFrom(error, GENERATE_ERROR);
    } finally {
      this.loading = false;
    }
  }

  /** Pause, resume, cancel, or complete, named by the button that was pressed. */
  async handleStatusChange(event) {
    const action = event.target.dataset.action;
    this.loading = true;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    try {
      this.absorb(await changeStatus({ commitmentId: this.recordId, action }));
      this.noticeMessage = STATUS_CHANGED;
    } catch (error) {
      this.errorMessage = this.messageFrom(error, LOAD_ERROR);
    } finally {
      this.loading = false;
    }
  }

  absorb(schedule) {
    this.installments = this.decorate(schedule);
    this.expectedTotal = schedule ? schedule.expectedTotal : undefined;
    this.commitmentStatus = schedule ? schedule.commitmentStatus : undefined;
  }

  /** Adds the badge class each status wears, so the template stays free of logic. */
  decorate(schedule) {
    const rows = schedule && schedule.installments ? schedule.installments : [];
    return rows.map((row) => ({
      ...row,
      key: row.recordId || `preview-${row.sequence}`,
      badgeClass: BADGE_BY_STATUS[row.status] || 'slds-theme_default'
    }));
  }

  messageFrom(error, fallback) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    return fallback;
  }
}
