import { LightningElement, api } from 'lwc';
import startServerExport from '@salesforce/apex/FindController.startServerExport';
import serverExportStatus from '@salesforce/apex/FindController.serverExportStatus';

import METER_LABEL from '@salesforce/label/c.Core_Find_ExportMenu';
import FILES from '@salesforce/label/c.Core_Find_ExportFilesList';
import NEW_TAB from '@salesforce/label/c.Core_Kit_NewTab';
import { messageFrom, format } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const POLL_MILLISECONDS = 5000;

/**
 * Find's export to Files (C-36, canonical model R-SQ12, admin guide find.md section 7.5a): starts
 * the server job for the query Find hands it, follows the job, and lists the CSV files it wrote
 * in the person's Files. Find calls `start`; nothing shows until then.
 */
export default class FindExportFiles extends LightningElement {
  helpReady = isHelpLoaded('Core');

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
  }

  job;
  errorMessage;
  timer;

  labels = { files: FILES, newTab: NEW_TAB, meterLabel: METER_LABEL };

  disconnectedCallback() {
    this.stopPolling();
  }

  /** Starts an export of `queryJson`, with each column's label by field path. */
  @api
  async start(queryJson, labelsByPath) {
    this.stopPolling();
    this.errorMessage = undefined;
    this.job = undefined;
    try {
      this.job = await startServerExport({
        queryJson,
        labelsJson: JSON.stringify(labelsByPath || {})
      });
      this.startPolling();
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  get hasError() {
    return Boolean(this.errorMessage);
  }

  /** Percent of the export written, from the job's parts done of parts total. */
  get progressValue() {
    const total = (this.job && this.job.chunksTotal) || 0;
    return total ? Math.round(((this.job.chunksDone || 0) * 100) / total) : 0;
  }

  /** The bar shows while the export runs and its size is known; before that, the started notice. */
  get showMeter() {
    return Boolean(this.job && !this.job.done && this.job.chunksTotal);
  }

  get statusLine() {
    if (!this.job) {
      return '';
    }
    if (!this.job.done) {
      return this.job.chunksTotal
        ? helpText('Core', 'Core_Find_ExportFilesProgress', this.progressValue)
        : helpText('Core', 'Core_Find_ExportFilesStarted');
    }
    return this.job.failed
      ? helpText('Core', 'Core_Find_ExportFilesFailed')
      : format(helpText('Core', 'Core_Find_ExportFilesDone'), (this.job.files || []).length);
  }

  get noticeVariant() {
    if (this.job && this.job.failed) {
      return 'warning';
    }
    return this.job && this.job.done ? 'success' : 'info';
  }

  get files() {
    return ((this.job && this.job.files) || []).map((file) => ({
      ...file,
      url: `/sfc/servlet.shepherd/document/download/${file.documentId}`
    }));
  }

  get hasFiles() {
    return this.files.length > 0;
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
      this.job = await serverExportStatus({ jobId: this.job.jobId, tag: this.job.tag });
      if (this.job.done) {
        this.stopPolling();
      }
    } catch (error) {
      this.stopPolling();
      this.errorMessage = messageFrom(error);
    }
  }
}
