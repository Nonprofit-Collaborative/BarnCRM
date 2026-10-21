import { LightningElement, api } from 'lwc';
import startServerExport from '@salesforce/apex/FindController.startServerExport';
import serverExportStatus from '@salesforce/apex/FindController.serverExportStatus';

import UNEXPECTED_ERROR from '@salesforce/label/c.Core_UnexpectedError';
import STARTED from '@salesforce/label/c.Core_Find_ExportFilesStarted';
import PROGRESS from '@salesforce/label/c.Core_Find_ExportFilesProgress';
import DONE from '@salesforce/label/c.Core_Find_ExportFilesDone';
import FAILED from '@salesforce/label/c.Core_Find_ExportFilesFailed';
import FILES from '@salesforce/label/c.Core_Find_ExportFilesList';

const POLL_MILLISECONDS = 5000;

function format(template, ...values) {
  return values.reduce((text, value, index) => text.split(`{${index}}`).join(value), template);
}

function messageFrom(error) {
  if (error && error.body && error.body.message) {
    return error.body.message;
  }
  return error && error.message ? error.message : UNEXPECTED_ERROR;
}

/**
 * Find's export to Files (C-36, canonical model R-SQ12, admin guide find.md section 7.5a): starts
 * the server job for the query Find hands it, follows the job, and lists the CSV files it wrote
 * in the person's Files. Find calls `start`; nothing shows until then.
 */
export default class FindExportFiles extends LightningElement {
  job;
  errorMessage;
  timer;

  labels = { files: FILES };

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

  get statusLine() {
    if (!this.job) {
      return '';
    }
    if (!this.job.done) {
      return this.job.chunksTotal
        ? format(PROGRESS, this.job.chunksDone || 0, this.job.chunksTotal)
        : STARTED;
    }
    return this.job.failed ? FAILED : format(DONE, (this.job.files || []).length);
  }

  get statusClass() {
    const theme = this.job && this.job.failed ? 'slds-theme_warning' : 'slds-theme_info';
    return `slds-box slds-box_x-small slds-var-m-vertical_small ${theme}`;
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
