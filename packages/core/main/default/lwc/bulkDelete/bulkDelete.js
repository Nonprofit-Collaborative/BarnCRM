import { LightningElement, api } from 'lwc';
import previewDelete from '@salesforce/apex/BulkDeleteController.preview';
import startDelete from '@salesforce/apex/BulkDeleteController.start';
import getJob from '@salesforce/apex/BulkDeleteController.getJob';
import previewFile from '@salesforce/apex/BulkDeleteController.previewFile';
import startFile from '@salesforce/apex/BulkDeleteController.startFile';
import backupPage from '@salesforce/apex/BulkDeleteController.backupPage';
import { messageFrom, format, downloadCsv } from 'c/findCsv';
import { startPolling } from 'c/jobPoller';
import BACKUP from '@salesforce/label/c.Core_BulkDelete_Backup';

import TITLE from '@salesforce/label/c.Core_BulkDelete_Title';
import DELETE_BUTTON from '@salesforce/label/c.Core_BulkDelete_DeleteButton';
import PREVIEW from '@salesforce/label/c.Core_BulkUpdate_Preview';
import CONFIRM from '@salesforce/label/c.Core_BulkUpdate_Confirm';
import UNDO_UNTIL from '@salesforce/label/c.Core_BulkUpdate_UndoUntil';
import FAILURES from '@salesforce/label/c.Core_BulkUpdate_Failures';
import CLOSE from '@salesforce/label/c.Core_BulkUpdate_Close';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';
import PATH_PREVIEW from '@salesforce/label/c.Core_Import_StepPreview';
import PATH_CONFIRM from '@salesforce/label/c.Core_BulkUpdate_PathConfirm';
import PATH_RUN from '@salesforce/label/c.Core_BulkUpdate_PathRun';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const STEPS = [
  { value: 'preview', label: PATH_PREVIEW },
  { value: 'confirm', label: PATH_CONFIRM },
  { value: 'run', label: PATH_RUN }
];

/**
 * Bulk delete (C-37, admin guide bulk-delete.md): every record a Find query returns, counted
 * and named in a preview with what Salesforce deletes with them, confirmed by typing the count,
 * deleted in the background as the person, with its progress.
 *
 * Find opens it over the query it just ran (`queryJson`). The page sends only the query document
 * and the confirmed count; BulkDeleteController checks both as the person (canonical model R-BD1
 * to R-BD6). Undo is in Data jobs on the Data Manager tab (dataJobHistory).
 *
 * The import wizard opens it over a delete by file's completed preview instead (`batchId`,
 * R-BD7): the records are the preview's Matched rows, and the page sends the batch and the count.
 *
 * Before the count is typed, "Download these records first" reads the records the delete would
 * delete, every field the person may read, page by page, and saves them as CSV (R-BD8, R-SQ3).
 */
export default class BulkDelete extends LightningElement {
  helpReady = isHelpLoaded('Core');

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
  }

  @api queryJson;
  /** A delete by file's import batch, in place of a query (R-BD7). */
  @api batchId;

  labels = {
    title: TITLE,
    get cascades() {
      return helpText('Core', 'Core_BulkDelete_Cascades');
    },
    preview: PREVIEW,
    confirm: CONFIRM,
    undoUntil: UNDO_UNTIL,
    failures: FAILURES,
    get undoFromTab() {
      return helpText('Core', 'Core_BulkDelete_UndoFromTab');
    },
    close: CLOSE,
    run: PATH_RUN,
    loading: LOADING,
    backup: BACKUP,
    get backupHelp() {
      return helpText('Core', 'Core_BulkDelete_BackupHelp');
    }
  };

  preview;
  confirmText = '';
  job;
  busy = false;
  errorMessage;
  noticeMessage;
  stopTimer;

  disconnectedCallback() {
    this.stopPolling();
  }

  steps = STEPS;

  /** The path: Preview until one shows, Confirm while it shows, Run once a job started. */
  get currentStep() {
    if (this.job) {
      return 'run';
    }
    return this.preview ? 'confirm' : 'preview';
  }

  get intro() {
    return this.batchId
      ? helpText('Core', 'Core_BulkDelete_FileIntro')
      : helpText('Core', 'Core_BulkDelete_PanelIntro');
  }

  get hasError() {
    return Boolean(this.errorMessage);
  }

  get hasNotice() {
    return Boolean(this.noticeMessage);
  }

  get previewLine() {
    return this.preview
      ? format(
          helpText('Core', 'Core_BulkDelete_PreviewCount'),
          this.preview.count,
          this.preview.objectLabel
        )
      : '';
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
    const percent = total ? Math.round(((job.chunksDone || 0) * 100) / total) : 0;
    return {
      ...job,
      summary: format(
        helpText('Core', 'Core_BulkDelete_Summary'),
        job.matched,
        job.deleted,
        job.failed
      ),
      progressLine: job.running ? helpText('Core', 'Core_BulkDelete_Progress', percent) : '',
      progressValue: percent,
      hasFailures: Boolean(job.failures && job.failures.length),
      showUndo: Boolean(job.canUndo && !job.running)
    };
  }

  async handlePreview() {
    this.noticeMessage = undefined;
    this.confirmText = '';
    this.preview = undefined;
    await this.work(async () => {
      this.preview = this.batchId
        ? await previewFile({ batchId: this.batchId })
        : await previewDelete({ queryJson: this.queryJson });
    });
  }

  handleConfirmText(event) {
    this.confirmText = event.detail.value;
  }

  /** Reads every record the delete would delete, page by page, and saves them as CSV (R-BD8). */
  async handleBackup() {
    this.noticeMessage = undefined;
    await this.work(async () => {
      let rows = [];
      let page;
      let afterId = null;
      do {
        // Each page starts after the last Id of the one before, so pages are read in turn.
        // eslint-disable-next-line no-await-in-loop
        page = await backupPage({
          queryJson: this.batchId ? null : this.queryJson,
          batchId: this.batchId || null,
          afterId
        });
        rows = rows.concat(page.rows || []);
        afterId = page.lastId;
        this.noticeMessage = format(
          helpText('Core', 'Core_BulkDelete_BackingUp'),
          String(rows.length)
        );
      } while (!page.done);
      const columns = (page.columns || []).map((column) => ({
        label: column.label,
        path: column.fieldName
      }));
      downloadCsv(page.objectName, columns, rows);
      this.noticeMessage = format(
        helpText('Core', 'Core_BulkDelete_BackupDone'),
        String(rows.length)
      );
    });
  }

  async handleStart() {
    await this.work(async () => {
      const confirmedCount = this.preview.count;
      this.job = this.batchId
        ? await startFile({ batchId: this.batchId, confirmedCount })
        : await startDelete({ queryJson: this.queryJson, confirmedCount });
      this.noticeMessage = helpText('Core', 'Core_BulkDelete_Started');
      this.preview = undefined;
      this.confirmText = '';
      this.startPolling();
    });
  }

  /** Slows down after the first minute and retries once on an error (c/jobPoller, FINDB-19). */
  startPolling() {
    this.stopPolling();
    this.stopTimer = startPolling(
      () => this.poll(),
      (error) => {
        this.errorMessage = messageFrom(error, String(error));
      }
    );
  }

  stopPolling() {
    if (this.stopTimer) {
      this.stopTimer();
      this.stopTimer = undefined;
    }
  }

  /** One read of the job; true once it has finished. */
  async poll() {
    this.job = await getJob({ jobId: this.job.recordId });
    if (!this.job.running) {
      this.stopPolling();
      this.noticeMessage = undefined;
      return true;
    }
    return false;
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
      this.errorMessage = messageFrom(error, String(error));
    } finally {
      this.busy = false;
    }
  }
}
