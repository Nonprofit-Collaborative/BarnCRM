import { LightningElement, api } from 'lwc';
import getRow from '@salesforce/apex/ImportRowCorrectionController.getRow';
import saveCorrections from '@salesforce/apex/ImportRowCorrectionController.saveCorrections';
import retryRow from '@salesforce/apex/ImportRowCorrectionController.retryRow';
import retryAllFixed from '@salesforce/apex/ImportRowCorrectionController.retryAllFixed';

import TITLE from '@salesforce/label/c.Core_ImportRow_Title';
import HELP from '@salesforce/label/c.Core_ImportRow_Help';
import STATUS_LABEL from '@salesforce/label/c.Core_ImportRow_StatusLabel';
import IMPORT_LABEL from '@salesforce/label/c.Core_ImportRow_ImportLabel';
import REASON_HEADING from '@salesforce/label/c.Core_ImportRow_ReasonHeading';
import COLUMN_HEADER from '@salesforce/label/c.Core_ImportRow_ColumnHeader';
import FILE_VALUE_HEADER from '@salesforce/label/c.Core_ImportRow_FileValueHeader';
import CORRECTED_HEADER from '@salesforce/label/c.Core_ImportRow_CorrectedHeader';
import SAVE from '@salesforce/label/c.Core_ImportRow_Save';
import RETRY_ROW from '@salesforce/label/c.Core_ImportRow_RetryRow';
import RETRY_ALL from '@salesforce/label/c.Core_ImportRow_RetryAll';
import FIXED_COUNT from '@salesforce/label/c.Core_ImportRow_FixedCount';
import REFRESH from '@salesforce/label/c.Core_ImportRow_Refresh';
import SAVED from '@salesforce/label/c.Core_ImportRow_Saved';
import RETRY_STARTED from '@salesforce/label/c.Core_ImportRow_RetryStarted';
import NO_VALUES from '@salesforce/label/c.Core_ImportRow_NoValues';
import LOADING from '@salesforce/label/c.Core_ImportRow_Loading';
import UNEXPECTED_ERROR from '@salesforce/label/c.Core_UnexpectedError';

// ImportRowProcessor.STATUS_REJECTED
const REJECTED = 'Rejected';

function errorText(error) {
  if (error && error.body && error.body.message) {
    return error.body.message;
  }
  return (error && error.message) || UNEXPECTED_ERROR;
}

/**
 * The Super Importer Row card on an import row's record page (C-49b): each column's file value
 * beside its correction and the reason the row was rejected; for a rejected row the person may
 * correct, the corrections can be saved and the row, or every corrected row of its import,
 * retried in place. The file's own values are never changed (R-IR4, R-IB17a).
 * See docs/admin-guide/import-rows.md.
 */
export default class ImportRowCorrection extends LightningElement {
  @api recordId;

  row;
  /** The values typed so far, by column, while the person edits. */
  edits = {};
  loading = true;
  busy = false;
  message;
  errorMessage;

  labels = {
    TITLE,
    HELP,
    STATUS_LABEL,
    IMPORT_LABEL,
    REASON_HEADING,
    COLUMN_HEADER,
    FILE_VALUE_HEADER,
    CORRECTED_HEADER,
    SAVE,
    RETRY_ROW,
    RETRY_ALL,
    REFRESH,
    NO_VALUES,
    LOADING
  };

  connectedCallback() {
    this.load();
  }

  async load() {
    this.loading = true;
    try {
      this.show(await getRow({ rowId: this.recordId }));
    } catch (error) {
      this.errorMessage = errorText(error);
    }
    this.loading = false;
  }

  show(row) {
    this.row = row;
    this.edits = {};
    this.errorMessage = undefined;
  }

  get hasRow() {
    return Boolean(this.row);
  }

  get isRejected() {
    return this.hasRow && this.row.status === REJECTED;
  }

  get canCorrect() {
    return this.hasRow && this.row.canCorrect === true;
  }

  get readOnly() {
    return !this.canCorrect;
  }

  get refusal() {
    return this.isRejected ? this.row.refusal : undefined;
  }

  get hasColumns() {
    return this.hasRow && Array.isArray(this.row.columns) && this.row.columns.length > 0;
  }

  get columns() {
    return (this.hasRow ? this.row.columns || [] : []).map((column) => {
      const value = Object.prototype.hasOwnProperty.call(this.edits, column.column)
        ? this.edits[column.column]
        : column.correctedValue;
      return {
        ...column,
        value,
        changed: value !== column.fileValue,
        rowClass: value !== column.fileValue ? 'slds-is-edited' : ''
      };
    });
  }

  get importUrl() {
    return this.hasRow ? `/lightning/r/${this.row.batchId}/view` : undefined;
  }

  get fixedCountText() {
    const count = this.hasRow ? this.row.fixedCount || 0 : 0;
    return count > 0 ? FIXED_COUNT.replace('{0}', count) : undefined;
  }

  get controlsDisabled() {
    return this.busy || this.readOnly;
  }

  get retryAllDisabled() {
    return this.controlsDisabled || !(this.row.fixedCount > 0 || this.isDirty);
  }

  get isDirty() {
    return Object.keys(this.edits).length > 0;
  }

  handleInput(event) {
    this.edits = { ...this.edits, [event.target.dataset.column]: event.target.value };
    this.message = undefined;
  }

  /** Every column's value as it stands on screen, so Apex keeps only what differs. */
  corrections() {
    const result = {};
    this.columns.forEach((column) => {
      result[column.column] = column.value;
    });
    return JSON.stringify(result);
  }

  async save() {
    const correctionsJson = this.corrections();
    this.show(await saveCorrections({ rowId: this.recordId, correctionsJson }));
  }

  async handleSave() {
    await this.run(async () => {
      await this.save();
      this.message = SAVED;
    });
  }

  /** Unsaved edits are saved first, so a retry always reads what is on screen. */
  async handleRetryRow() {
    await this.run(async () => {
      if (this.isDirty) {
        await this.save();
      }
      await retryRow({ rowId: this.recordId });
      this.message = RETRY_STARTED;
    });
  }

  async handleRetryAll() {
    await this.run(async () => {
      if (this.isDirty) {
        await this.save();
      }
      await retryAllFixed({ rowId: this.recordId });
      this.message = RETRY_STARTED;
    });
  }

  async handleRefresh() {
    this.message = undefined;
    await this.load();
  }

  async run(action) {
    this.busy = true;
    this.errorMessage = undefined;
    try {
      await action();
    } catch (error) {
      this.message = undefined;
      this.errorMessage = errorText(error);
    }
    this.busy = false;
  }
}
