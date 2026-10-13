import { LightningElement } from 'lwc';
import getPage from '@salesforce/apex/BulkUpdateController.getPage';
import undoUpdate from '@salesforce/apex/BulkUpdateController.undo';

import TITLE from '@salesforce/label/c.Core_BulkUpdate_Title';
import TAB_INTRO from '@salesforce/label/c.Core_BulkUpdate_TabIntro';
import SUMMARY from '@salesforce/label/c.Core_BulkUpdate_Summary';
import RECENT from '@salesforce/label/c.Core_BulkUpdate_Recent';
import NO_JOBS from '@salesforce/label/c.Core_BulkUpdate_NoJobs';
import REFRESH from '@salesforce/label/c.Core_BulkUpdate_Refresh';
import UNDO from '@salesforce/label/c.Core_BulkUpdate_Undo';
import UNDO_CONFIRM from '@salesforce/label/c.Core_BulkUpdate_UndoConfirm';
import UNDO_BUTTON from '@salesforce/label/c.Core_BulkUpdate_UndoButton';
import UNDO_STARTED from '@salesforce/label/c.Core_BulkUpdate_UndoStarted';
import UNDO_UNTIL from '@salesforce/label/c.Core_BulkUpdate_UndoUntil';
import CONFIRM from '@salesforce/label/c.Core_BulkUpdate_Confirm';
import CANCEL from '@salesforce/label/c.Core_BulkUpdate_Cancel';
import LOADING from '@salesforce/label/c.Core_BulkUpdate_Loading';
import EVERYONE from '@salesforce/label/c.Core_BulkUpdate_EveryonesJobs';

function format(template, ...values) {
  return values.reduce((text, value, index) => text.split(`{${index}}`).join(value), template);
}

/**
 * The Bulk Update tab (C-35, admin guide bulk-update.md): recent bulk updates with what each
 * did, and their undo, confirmed by typing the number of records it puts back (canonical model
 * R-BU5). Renders nothing for a person without the bulk update permissions, since the tab is
 * shared with bulk delete. A bulk update itself is started from Find, by the bulkUpdate panel.
 */
export default class BulkUpdateHistory extends LightningElement {
  labels = {
    title: TITLE,
    intro: TAB_INTRO,
    recent: RECENT,
    noJobs: NO_JOBS,
    refresh: REFRESH,
    undo: UNDO,
    undoButton: UNDO_BUTTON,
    undoUntil: UNDO_UNTIL,
    confirm: CONFIRM,
    cancel: CANCEL,
    loading: LOADING,
    everyone: EVERYONE
  };

  allowed = false;
  /** Whether the person may list everyone's jobs, and whether they asked to. */
  canSeeEveryone = false;
  everyone = false;
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
      const page = await getPage({ everyone: this.everyone });
      this.allowed = Boolean(page && page.allowed);
      this.canSeeEveryone = Boolean(page && page.canSeeEveryone);
      this.jobs = (page && page.jobs) || [];
    });
  }

  handleEveryone(event) {
    this.everyone = event.target.checked;
    this.load();
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
      summary: format(SUMMARY, job.matched, job.updated, job.unchanged, job.failed),
      showUndo: Boolean(job.canUndo && !job.running)
    }));
  }

  get undoLine() {
    return this.undoTarget ? format(UNDO_CONFIRM, this.undoTarget.updatesToUndo) : '';
  }

  get undoDisabled() {
    return (
      this.busy ||
      !this.undoTarget ||
      String(this.undoText).trim() !== String(this.undoTarget.updatesToUndo)
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
      const undone = await undoUpdate({
        jobId: this.undoTarget.recordId,
        confirmedUpdates: this.undoTarget.updatesToUndo
      });
      this.jobs = this.jobs.map((job) => {
        return job.recordId === undone.recordId ? undone : job;
      });
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
