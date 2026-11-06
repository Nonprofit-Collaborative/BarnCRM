import { LightningElement, api } from 'lwc';
import getSchedule from '@salesforce/apex/CommitmentController.getSchedule';
import generateNow from '@salesforce/apex/CommitmentController.generateNow';
import changeStatus from '@salesforce/apex/CommitmentController.changeStatus';

import TITLE from '@salesforce/label/c.Giving_SchedulePreview_Title';
import GENERATE_NOW from '@salesforce/label/c.Giving_SchedulePreview_GenerateNow';
import GENERATED from '@salesforce/label/c.Giving_SchedulePreview_Generated';
import GENERATE_ERROR from '@salesforce/label/c.Giving_SchedulePreview_GenerateError';
import LOAD_ERROR from '@salesforce/label/c.Giving_SchedulePreview_LoadError';
import COLUMN_SEQUENCE from '@salesforce/label/c.Giving_Receipt_ColumnNumber';
import COLUMN_DUE_DATE from '@salesforce/label/c.Giving_SchedulePreview_ColumnDueDate';
import COLUMN_AMOUNT from '@salesforce/label/c.Giving_SchedulePreview_ColumnAmount';
import COLUMN_PAID from '@salesforce/label/c.Giving_SchedulePreview_ColumnPaid';
import COLUMN_STATUS from '@salesforce/label/c.Core_ImportRow_StatusLabel';
import TOTAL from '@salesforce/label/c.Giving_SchedulePreview_Total';
import ACTION_PAUSE from '@salesforce/label/c.Giving_Commitment_ActionPause';
import ACTION_RESUME from '@salesforce/label/c.Giving_Commitment_ActionResume';
import ACTION_CANCEL from '@salesforce/label/c.Giving_Commitment_ActionCancel';
import ACTION_COMPLETE from '@salesforce/label/c.Giving_Commitment_ActionComplete';
import STATUS_CHANGED from '@salesforce/label/c.Giving_Commitment_StatusChanged';
import CANCEL_TITLE from '@salesforce/label/c.Giving_Commitment_CancelConfirmTitle';
import KEEP_IT from '@salesforce/label/c.Core_Find_DeleteConfirmCancel';
import EMPTY_HEADING from '@salesforce/label/c.Giving_SchedulePreview_EmptyHeading';
import BarnConfirmModal from 'c/barnConfirmModal';
import { bodyMessage } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

/** Each payment status in the suite's status vocabulary (c/barnStatus). */
const TONE_BY_STATUS = {
  Paid: 'success',
  'Partially paid': 'warning',
  Overdue: 'overdue',
  Skipped: 'skipped'
};
const SETTLED_STATUSES = ['Paid', 'Partially paid', 'Skipped'];

/**
 * The payment schedule of a commitment, shown on the commitment record page: what is due,
 * when, what has been paid, and where each payment stands. When a commitment has no
 * schedule yet, it offers to generate one.
 */
export default class CommitmentSchedulePreview extends LightningElement {
  helpReady = isHelpLoaded('Giving');

  @api recordId;

  installments = [];
  expectedTotal;
  commitmentStatus;
  canChange = false;
  canGenerate = false;
  loading = true;
  errorMessage;
  noticeMessage;

  labels = {
    title: TITLE,
    emptyHeading: EMPTY_HEADING,
    get empty() {
      return helpText('Giving', 'Giving_SchedulePreview_Empty');
    },
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
    if (!this.helpReady) {
      loadHelp('Giving').then(() => {
        this.helpReady = true;
      });
    }
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

  /** A person who may only read the commitment is offered no change at all. */
  get hasActions() {
    return this.canChange && (this.canPause || this.canResume || this.canEnd);
  }

  async load() {
    this.loading = true;
    this.errorMessage = undefined;
    try {
      this.absorb(await getSchedule({ commitmentId: this.recordId }));
    } catch (error) {
      this.installments = [];
      this.errorMessage = bodyMessage(error, LOAD_ERROR);
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
      this.errorMessage = bodyMessage(error, GENERATE_ERROR);
    } finally {
      this.loading = false;
    }
  }

  /** Pause, resume or complete, named by the button that was pressed. */
  handleStatusChange(event) {
    return this.changeStatus(event.target.dataset.action);
  }

  /** The payments a cancel marks Skipped: nothing paid on them yet. */
  get unpaidCount() {
    return this.installments.filter(
      (row) => !SETTLED_STATUSES.includes(row.status) && !(Number(row.paidAmount) > 0)
    ).length;
  }

  /** Cancelling skips every unpaid payment, so it is asked about first (people-giving-2). */
  async handleCancel() {
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: CANCEL_TITLE,
      message: helpText('Giving', 'Giving_SchedulePreview_CancelMessage', String(this.unpaidCount)),
      cancelLabel: KEEP_IT,
      confirmLabel: ACTION_CANCEL,
      confirmVariant: 'destructive-text'
    });
    if (confirmed === true) {
      await this.changeStatus('cancel');
    }
  }

  async changeStatus(action) {
    this.loading = true;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    try {
      this.absorb(await changeStatus({ commitmentId: this.recordId, action }));
      this.noticeMessage = STATUS_CHANGED;
    } catch (error) {
      this.errorMessage = bodyMessage(error, LOAD_ERROR);
    } finally {
      this.loading = false;
    }
  }

  absorb(schedule) {
    this.installments = this.decorate(schedule);
    this.expectedTotal = schedule ? schedule.expectedTotal : undefined;
    this.commitmentStatus = schedule ? schedule.commitmentStatus : undefined;
    this.canChange = Boolean(schedule && schedule.canChange);
    this.canGenerate = Boolean(schedule && schedule.canGenerate);
  }

  /** Adds the tone each status wears, so the template stays free of logic. */
  decorate(schedule) {
    const rows = schedule && schedule.installments ? schedule.installments : [];
    return rows.map((row) => ({
      ...row,
      key: row.recordId || `preview-${row.sequence}`,
      tone: TONE_BY_STATUS[row.status] || 'neutral'
    }));
  }
}
