import { LightningElement } from 'lwc';
import getHours from '@salesforce/apex/VolunteerHoursApprovalController.getHours';
import approveHours from '@salesforce/apex/VolunteerHoursApprovalController.approve';
import rejectHours from '@salesforce/apex/VolunteerHoursApprovalController.reject';
import reopenHours from '@salesforce/apex/VolunteerHoursApprovalController.reopen';

import TITLE from '@salesforce/label/c.Volunteers_Approve_Title';
import READ_ONLY from '@salesforce/label/c.Volunteers_Hours_NeedManagePermission';
import SHOW from '@salesforce/label/c.Volunteers_Approve_Show';
import SUBMITTED from '@salesforce/label/c.Volunteers_Approve_StatusSubmitted';
import APPROVED from '@salesforce/label/c.Volunteers_Approve_StatusApproved';
import REJECTED from '@salesforce/label/c.Volunteers_Approve_StatusRejected';
import JOB from '@salesforce/label/c.Volunteers_Approve_Job';
import FROM_DATE from '@salesforce/label/c.Volunteers_Approve_From';
import TO_DATE from '@salesforce/label/c.Volunteers_Approve_To';
import PERSON from '@salesforce/label/c.Volunteers_Approve_Person';
import SHIFT from '@salesforce/label/c.Volunteers_Approve_Shift';
import DATE_WORKED from '@salesforce/label/c.Volunteers_Approve_DateWorked';
import HOURS from '@salesforce/label/c.Volunteers_Approve_Hours';
import REASON_COLUMN from '@salesforce/label/c.Volunteers_Approve_ReasonColumn';
import SELECT from '@salesforce/label/c.Volunteers_Approve_Select';
import SELECT_ALL from '@salesforce/label/c.Volunteers_Approve_SelectAll';
import SELECT_ROW from '@salesforce/label/c.Volunteers_Approve_SelectRow';
import CAPTION from '@salesforce/label/c.Volunteers_Approve_Caption';
import SELECTED_COUNT from '@salesforce/label/c.Volunteers_Approve_SelectedCount';
import APPROVE from '@salesforce/label/c.Volunteers_Approve_Approve';
import REJECT from '@salesforce/label/c.Volunteers_Approve_Reject';
import REOPEN from '@salesforce/label/c.Volunteers_Approve_Reopen';
import REASON from '@salesforce/label/c.Volunteers_Approve_Reason';
import CONFIRM_REJECT from '@salesforce/label/c.Volunteers_Approve_ConfirmReject';
import CANCEL from '@salesforce/label/c.Volunteers_Approve_Cancel';
import PREVIOUS from '@salesforce/label/c.Volunteers_Approve_Previous';
import NEXT from '@salesforce/label/c.Volunteers_Approve_Next';
import PAGE from '@salesforce/label/c.Volunteers_Approve_Page';
import EMPTY from '@salesforce/label/c.Volunteers_Approve_Empty';
import DONE_APPROVE from '@salesforce/label/c.Volunteers_Approve_DoneApprove';
import DONE_REJECT from '@salesforce/label/c.Volunteers_Approve_DoneReject';
import DONE_REOPEN from '@salesforce/label/c.Volunteers_Approve_DoneReopen';
import REFUSED from '@salesforce/label/c.Volunteers_Approve_Refused';
import REASON_REQUIRED from '@salesforce/label/c.Volunteers_Hours_RejectionReasonRequired';
import ACTION_FAILED from '@salesforce/label/c.Volunteers_Approve_ActionFailed';
import DATE_RANGE from '@salesforce/label/c.Volunteers_Approve_DateRange';
import LOADING from '@salesforce/label/c.Volunteers_Loading';
import { bodyMessage, format } from 'c/findCsv';

const STATUS_SUBMITTED = 'Submitted';
const STATUS_APPROVED = 'Approved';
const STATUS_REJECTED = 'Rejected';
const STATUS_LABELS = {
  [STATUS_SUBMITTED]: SUBMITTED,
  [STATUS_APPROVED]: APPROVED,
  [STATUS_REJECTED]: REJECTED
};

/** A yyyy-mm-dd date as people read dates, for a screen reader; the raw value if it is not one. */
function readableDate(value) {
  const date = new Date(`${value}T00:00:00Z`);
  if (!value || Number.isNaN(date.getTime())) {
    return value;
  }
  return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeZone: 'UTC' }).format(date);
}

/**
 * The Approve Hours screen (V-02): the hours waiting for a coordinator, a page at a time, with
 * Approve, Reject (with a reason) and Reopen. Every change goes through the server's hours
 * service; this screen only chooses which entries.
 */
export default class VolunteerHoursApproval extends LightningElement {
  labels = {
    title: TITLE,
    readOnly: READ_ONLY,
    show: SHOW,
    job: JOB,
    fromDate: FROM_DATE,
    toDate: TO_DATE,
    person: PERSON,
    shift: SHIFT,
    dateWorked: DATE_WORKED,
    hours: HOURS,
    reasonColumn: REASON_COLUMN,
    select: SELECT,
    selectAll: SELECT_ALL,
    approve: APPROVE,
    reject: REJECT,
    reopen: REOPEN,
    reason: REASON,
    confirmReject: CONFIRM_REJECT,
    cancel: CANCEL,
    previous: PREVIOUS,
    next: NEXT,
    empty: EMPTY,
    reasonRequired: REASON_REQUIRED,
    loading: LOADING
  };

  statusOptions = [STATUS_SUBMITTED, STATUS_APPROVED, STATUS_REJECTED].map((value) => ({
    label: STATUS_LABELS[value],
    value
  }));

  status = STATUS_SUBMITTED;
  jobId;
  fromDate;
  toDate;
  /** The last row of each page before the current one: the cursor the server pages by. */
  pageStarts = [null];
  pageIndex = 0;
  page;
  selectedIds = [];
  busy = false;
  showReject = false;
  reason = '';
  errorMessage;
  resultMessage;
  refusedLines = [];
  focusResult = false;
  focusReason = false;
  focusRejectButton = false;
  /** Which paging control gets focus once the page has loaded: 'previous', 'next' or 'page-text'. */
  focusPaging;

  connectedCallback() {
    this.load();
  }

  renderedCallback() {
    if (this.focusReason) {
      const reasonInput = this.template.querySelector('[data-id="reason"]');
      if (reasonInput) {
        this.focusReason = false;
        reasonInput.focus();
      }
    }
    if (this.focusRejectButton) {
      const rejectButton = this.template.querySelector('[data-id="reject"]');
      if (rejectButton) {
        this.focusRejectButton = false;
        rejectButton.focus();
      }
    }
    if (this.focusPaging) {
      this.applyPagingFocus();
    }
    if (this.focusResult) {
      const region = this.template.querySelector('[data-id="result"]');
      if (region) {
        this.focusResult = false;
        region.focus();
      }
    }
  }

  // ----------------------------------------------------------------------------- the list

  load() {
    const start = this.pageStarts[this.pageIndex];
    this.busy = true;
    return getHours({
      status: this.status,
      jobId: this.jobId || null,
      fromDate: this.fromDate || null,
      toDate: this.toDate || null,
      afterDate: start ? start.dateWorked : null,
      afterId: start ? start.recordId : null
    })
      .then((page) => {
        this.page = page;
        this.selectedIds = [];
        this.errorMessage = undefined;
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, ACTION_FAILED);
      })
      .finally(() => {
        this.busy = false;
      });
  }

  /** A filter changed: back to the first page, and nothing selected. */
  restart() {
    this.pageStarts = [null];
    this.pageIndex = 0;
    this.showReject = false;
    return this.load();
  }

  get loaded() {
    return !!this.page;
  }

  get canManage() {
    return !!(this.page && this.page.canManage);
  }

  get showReadOnly() {
    return this.loaded && !this.canManage;
  }

  get rows() {
    const rows = this.page && this.page.rows ? this.page.rows : [];
    return rows.map((row) => ({
      ...row,
      selected: this.selectedIds.includes(row.recordId),
      selectLabel: format(
        SELECT_ROW,
        row.personName || row.name,
        readableDate(row.dateWorked),
        row.hours
      )
    }));
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get isEmpty() {
    return this.loaded && !this.hasRows;
  }

  get showReasonColumn() {
    return this.status === STATUS_REJECTED;
  }

  get caption() {
    return format(CAPTION, STATUS_LABELS[this.status], this.pageIndex + 1);
  }

  get pageText() {
    return format(PAGE, this.pageIndex + 1);
  }

  get allSelected() {
    return this.hasRows && this.selectedIds.length === this.rows.length;
  }

  get selectedText() {
    return format(SELECTED_COUNT, this.selectedIds.length);
  }

  get noneSelected() {
    return this.busy || this.selectedIds.length === 0;
  }

  get showApprove() {
    return this.status === STATUS_SUBMITTED;
  }

  get showRejectButton() {
    return this.status === STATUS_SUBMITTED;
  }

  get showReopen() {
    return this.status !== STATUS_SUBMITTED;
  }

  get previousDisabled() {
    return this.busy || this.pageIndex === 0;
  }

  get nextDisabled() {
    return this.busy || !(this.page && this.page.hasMore);
  }

  get hasError() {
    return !!this.errorMessage;
  }

  get hasRefused() {
    return this.refusedLines.length > 0;
  }

  // ------------------------------------------------------------------------------ filters

  handleStatusChange(event) {
    this.status = event.detail.value;
    return this.restart();
  }

  handleJobChange(event) {
    this.jobId = event.detail ? event.detail.recordId : undefined;
    return this.restart();
  }

  handleFromChange(event) {
    this.fromDate = event.detail.value;
    return this.dateFilterChanged(event.target);
  }

  handleToChange(event) {
    this.toDate = event.detail.value;
    return this.dateFilterChanged(event.target);
  }

  /** A From later than To is refused on the field that changed, without asking the server. */
  dateFilterChanged(changedInput) {
    const fromInput = this.template.querySelector('[data-id="from-filter"]');
    const toInput = this.template.querySelector('[data-id="to-filter"]');
    [fromInput, toInput].forEach((input) => input && input.setCustomValidity(''));
    if (this.fromDate && this.toDate && this.fromDate > this.toDate) {
      const input = changedInput || toInput;
      input.setCustomValidity(DATE_RANGE);
      input.reportValidity();
      return Promise.resolve();
    }
    [fromInput, toInput].forEach((input) => input && input.reportValidity());
    return this.restart();
  }

  handleNext() {
    const rows = this.page.rows;
    this.pageStarts = [...this.pageStarts.slice(0, this.pageIndex + 1), rows[rows.length - 1]];
    this.pageIndex += 1;
    return this.load().then(() => {
      this.focusPaging = this.nextDisabled ? 'previous' : 'next';
      this.applyPagingFocus();
    });
  }

  handlePrevious() {
    this.pageIndex -= 1;
    return this.load().then(() => {
      if (!this.previousDisabled) {
        this.focusPaging = 'previous';
      } else {
        this.focusPaging = this.nextDisabled ? 'page-text' : 'next';
      }
      this.applyPagingFocus();
    });
  }

  /**
   * The paging buttons are disabled while a page loads, which drops focus; a button that ends up
   * disabled (Next on the last page, Previous on the first) hands focus to the other one, or to
   * the page status when neither can be used. Tries again after render if the target is not
   * ready yet.
   */
  applyPagingFocus() {
    const target = this.template.querySelector(`[data-id="${this.focusPaging}"]`);
    if (target && !target.disabled) {
      this.focusPaging = undefined;
      target.focus();
    }
  }

  // ---------------------------------------------------------------------------- selection

  handleSelectAll(event) {
    this.selectedIds = event.target.checked ? this.rows.map((row) => row.recordId) : [];
  }

  handleSelectRow(event) {
    const recordId = event.target.dataset.recordId;
    const others = this.selectedIds.filter((selected) => selected !== recordId);
    this.selectedIds = event.target.checked ? [...others, recordId] : others;
  }

  // -------------------------------------------------------------------------------- verbs

  handleApprove() {
    return this.act(approveHours({ hoursIds: this.selectedIds }), DONE_APPROVE);
  }

  handleReopen() {
    return this.act(reopenHours({ hoursIds: this.selectedIds }), DONE_REOPEN);
  }

  handleShowReject() {
    this.showReject = true;
    this.reason = '';
    this.focusReason = true;
  }

  handleReasonChange(event) {
    this.reason = event.detail.value;
  }

  /** Closes the form and puts focus back on Reject, where the user opened it. */
  handleCancelReject() {
    this.showReject = false;
    this.reason = '';
    this.focusRejectButton = true;
  }

  handleConfirmReject() {
    const reasonInput = this.template.querySelector('[data-id="reason"]');
    if (!this.reason || !this.reason.trim()) {
      if (reasonInput) {
        reasonInput.setCustomValidity(REASON_REQUIRED);
        reasonInput.reportValidity();
        reasonInput.focus();
      }
      return Promise.resolve();
    }
    if (reasonInput) {
      reasonInput.setCustomValidity('');
    }
    return this.act(
      rejectHours({ hoursIds: this.selectedIds, reason: this.reason }),
      DONE_REJECT
    ).then((outcome) => {
      // A refused call keeps the form open with the reason typed, so it can be sent again.
      if (outcome !== false) {
        this.showReject = false;
        this.reason = '';
      }
    });
  }

  /**
   * Runs one verb, reports what moved and what did not, and reloads the page. Resolves false
   * when the call was refused.
   */
  act(call, doneTemplate) {
    const namesById = {};
    this.rows.forEach((row) => {
      namesById[row.recordId] = row.personName ? `${row.name} (${row.personName})` : row.name;
    });
    this.busy = true;
    this.errorMessage = undefined;
    return call
      .then((result) => {
        this.resultMessage = format(doneTemplate, result.moved);
        this.refusedLines = (result.refused || []).map((refusal) => ({
          key: refusal.recordId,
          text: `${namesById[refusal.recordId] || refusal.recordId}: ${refusal.message}`
        }));
        // Announced once, by the status region; a toast as well would be read out twice.
        if (this.refusedLines.length) {
          this.resultMessage = `${this.resultMessage} ${format(REFUSED, this.refusedLines.length)}`;
        }
        this.focusResult = true;
        return this.load();
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, ACTION_FAILED);
        this.busy = false;
        return false;
      });
  }
}
