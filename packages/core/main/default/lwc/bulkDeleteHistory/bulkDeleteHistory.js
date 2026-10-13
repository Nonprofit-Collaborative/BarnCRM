import { LightningElement } from 'lwc';
import getPage from '@salesforce/apex/BulkDeleteController.getPage';
import undoDelete from '@salesforce/apex/BulkDeleteController.undo';

import RECENT from '@salesforce/label/c.Core_BulkDelete_Recent';
import NO_JOBS from '@salesforce/label/c.Core_BulkDelete_NoJobs';
import SUMMARY from '@salesforce/label/c.Core_BulkDelete_Summary';
import UNDO_CONFIRM from '@salesforce/label/c.Core_BulkDelete_UndoConfirm';
import UNDO_BUTTON from '@salesforce/label/c.Core_BulkDelete_UndoButton';
import REFRESH from '@salesforce/label/c.Core_BulkUpdate_Refresh';
import UNDO from '@salesforce/label/c.Core_BulkUpdate_Undo';
import UNDO_STARTED from '@salesforce/label/c.Core_BulkUpdate_UndoStarted';
import UNDO_UNTIL from '@salesforce/label/c.Core_BulkUpdate_UndoUntil';
import CONFIRM from '@salesforce/label/c.Core_BulkUpdate_Confirm';
import CANCEL from '@salesforce/label/c.Core_BulkUpdate_Cancel';
import LOADING from '@salesforce/label/c.Core_BulkUpdate_Loading';

function format(template, ...values) {
  return values.reduce((text, value, index) => text.split(`{${index}}`).join(value), template);
}

/**
 * Recent bulk deletes on the Bulk Update tab (C-37, admin guide bulk-delete.md), with their
 * undo from the Recycle Bin, confirmed by typing the number of records it brings back
 * (canonical model R-BD5). Renders nothing for a person without the bulk delete permissions,
 * since the tab is shared with bulk update. A bulk delete itself is started from Find.
 */
export default class BulkDeleteHistory extends LightningElement {
  labels = {
    recent: RECENT,
    noJobs: NO_JOBS,
    refresh: REFRESH,
    undo: UNDO,
    undoButton: UNDO_BUTTON,
    undoUntil: UNDO_UNTIL,
    confirm: CONFIRM,
    cancel: CANCEL,
    loading: LOADING
  };

  allowed = false;
  jobs = [];
  undoTarget;
  undoText = '';
  busy = false;
  errorMessage;
  noticeMessage;

  connectedCallback() {
    this.load();
  }

  async load() {
    await this.work(async () => {
      const page = await getPage();
      this.allowed = Boolean(page && page.allowed);
      this.jobs = (page && page.jobs) || [];
    });
  }

  get hasError() {
    return Boolean(this.errorMessage);
  }

  get hasNotice() {
    return Boolean(this.noticeMessage);
  }

  get hasJobs() {
    return this.jobs.length > 0;
  }

  get jobRows() {
    return this.jobs.map((job) => ({
      ...job,
      summary: format(SUMMARY, job.matched, job.deleted, job.failed),
      showUndo: Boolean(job.canUndo && !job.running)
    }));
  }

  get undoLine() {
    return this.undoTarget ? format(UNDO_CONFIRM, this.undoTarget.recordsToUndo) : '';
  }

  get undoDisabled() {
    return (
      this.busy ||
      !this.undoTarget ||
      String(this.undoText).trim() !== String(this.undoTarget.recordsToUndo)
    );
  }

  async handleRefresh() {
    this.noticeMessage = undefined;
    await this.load();
  }

  handleUndo(event) {
    const jobId = event.currentTarget.dataset.id;
    this.undoTarget = this.jobs.find((job) => job.recordId === jobId);
    this.undoText = '';
    this.noticeMessage = undefined;
  }

  handleUndoText(event) {
    this.undoText = event.detail.value;
  }

  handleUndoCancel() {
    this.undoTarget = undefined;
    this.undoText = '';
  }

  async handleUndoConfirm() {
    await this.work(async () => {
      const undone = await undoDelete({
        jobId: this.undoTarget.recordId,
        confirmedRecords: this.undoTarget.recordsToUndo
      });
      this.jobs = this.jobs.map((job) => (job.recordId === undone.recordId ? undone : job));
      this.undoTarget = undefined;
      this.undoText = '';
      this.noticeMessage = UNDO_STARTED;
    });
  }

  async work(action) {
    this.busy = true;
    this.errorMessage = undefined;
    try {
      await action();
    } catch (error) {
      this.errorMessage =
        error && error.body && error.body.message
          ? error.body.message
          : (error && error.message) || String(error);
    } finally {
      this.busy = false;
    }
  }
}
