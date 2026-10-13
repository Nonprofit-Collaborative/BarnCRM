import { LightningElement, api } from 'lwc';
import previewDelete from '@salesforce/apex/BulkDeleteController.preview';
import startDelete from '@salesforce/apex/BulkDeleteController.start';
import getJob from '@salesforce/apex/BulkDeleteController.getJob';

import TITLE from '@salesforce/label/c.Core_BulkDelete_Title';
import PANEL_INTRO from '@salesforce/label/c.Core_BulkDelete_PanelIntro';
import PREVIEW_COUNT from '@salesforce/label/c.Core_BulkDelete_PreviewCount';
import CASCADES from '@salesforce/label/c.Core_BulkDelete_Cascades';
import DELETE_BUTTON from '@salesforce/label/c.Core_BulkDelete_DeleteButton';
import STARTED from '@salesforce/label/c.Core_BulkDelete_Started';
import PROGRESS from '@salesforce/label/c.Core_BulkDelete_Progress';
import SUMMARY from '@salesforce/label/c.Core_BulkDelete_Summary';
import UNDO_FROM_TAB from '@salesforce/label/c.Core_BulkDelete_UndoFromTab';
import PREVIEW from '@salesforce/label/c.Core_BulkUpdate_Preview';
import CONFIRM from '@salesforce/label/c.Core_BulkUpdate_Confirm';
import UNDO_UNTIL from '@salesforce/label/c.Core_BulkUpdate_UndoUntil';
import FAILURES from '@salesforce/label/c.Core_BulkUpdate_Failures';
import CLOSE from '@salesforce/label/c.Core_BulkUpdate_Close';
import LOADING from '@salesforce/label/c.Core_BulkUpdate_Loading';

const POLL_MILLISECONDS = 3000;

function format(template, ...values) {
  return values.reduce((text, value, index) => text.split(`{${index}}`).join(value), template);
}

/**
 * Bulk delete (C-37, admin guide bulk-delete.md): every record a Find query returns, counted
 * and named in a preview with what Salesforce deletes with them, confirmed by typing the count,
 * deleted in the background as the person, with its progress.
 *
 * Find opens it over the query it just ran (`queryJson`). The page sends only the query document
 * and the confirmed count; BulkDeleteController checks both as the person (canonical model R-BD1
 * to R-BD6). Undo is on the Bulk Update tab (bulkDeleteHistory).
 */
export default class BulkDelete extends LightningElement {
  @api queryJson;

  labels = {
    title: TITLE,
    panelIntro: PANEL_INTRO,
    cascades: CASCADES,
    preview: PREVIEW,
    confirm: CONFIRM,
    undoUntil: UNDO_UNTIL,
    failures: FAILURES,
    undoFromTab: UNDO_FROM_TAB,
    close: CLOSE,
    loading: LOADING
  };

  preview;
  confirmText = '';
  job;
  busy = false;
  errorMessage;
  noticeMessage;
  timer;

  disconnectedCallback() {
    this.stopPolling();
  }

  get hasError() {
    return Boolean(this.errorMessage);
  }

  get hasNotice() {
    return Boolean(this.noticeMessage);
  }

  get previewLine() {
    return this.preview ? format(PREVIEW_COUNT, this.preview.count, this.preview.objectLabel) : '';
  }

  get hasCascades() {
    return Boolean(this.preview && this.preview.cascades && this.preview.cascades.length);
  }

  get deleteLabel() {
    return format(DELETE_BUTTON, this.preview ? this.preview.count : 0);
  }

  get startDisabled() {
    return (
      this.busy || !this.preview || String(this.confirmText).trim() !== String(this.preview.count)
    );
  }

  get previewDisabled() {
    return this.busy || Boolean(this.job && this.job.running);
  }

  get jobView() {
    if (!this.job) {
      return undefined;
    }
    const job = this.job;
    const total = job.chunksTotal || 0;
    return {
      ...job,
      summary: format(SUMMARY, job.matched, job.deleted, job.failed),
      progressLine: job.running ? format(PROGRESS, job.chunksDone || 0, total) : '',
      progressValue: total ? Math.round(((job.chunksDone || 0) * 100) / total) : 0,
      hasFailures: Boolean(job.failures && job.failures.length),
      showUndo: Boolean(job.canUndo && !job.running)
    };
  }

  async handlePreview() {
    this.noticeMessage = undefined;
    this.confirmText = '';
    this.preview = undefined;
    await this.work(async () => {
      this.preview = await previewDelete({ queryJson: this.queryJson });
    });
  }

  handleConfirmText(event) {
    this.confirmText = event.detail.value;
  }

  async handleStart() {
    await this.work(async () => {
      this.job = await startDelete({
        queryJson: this.queryJson,
        confirmedCount: this.preview.count
      });
      this.noticeMessage = STARTED;
      this.preview = undefined;
      this.confirmText = '';
      this.startPolling();
    });
  }

  startPolling() {
    this.stopPolling();
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.timer = setInterval(() => this.poll(), POLL_MILLISECONDS);
  }

  stopPolling() {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = undefined;
    }
  }

  async poll() {
    try {
      this.job = await getJob({ jobId: this.job.recordId });
      if (!this.job.running) {
        this.stopPolling();
        this.noticeMessage = undefined;
      }
    } catch (error) {
      this.stopPolling();
      this.errorMessage = messageFrom(error);
    }
  }

  handleClose() {
    this.stopPolling();
    this.dispatchEvent(new CustomEvent('close'));
  }

  async work(action) {
    this.busy = true;
    this.errorMessage = undefined;
    try {
      await action();
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.busy = false;
    }
  }
}

function messageFrom(error) {
  if (error && error.body && error.body.message) {
    return error.body.message;
  }
  return error && error.message ? error.message : String(error);
}
