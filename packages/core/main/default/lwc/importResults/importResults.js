import { LightningElement, api } from 'lwc';

import previewWouldCreate from '@salesforce/label/c.Core_Import_PreviewWouldCreate';
import previewWouldUpdate from '@salesforce/label/c.Core_Import_PreviewWouldUpdate';
import previewWouldMatch from '@salesforce/label/c.Core_Import_PreviewWouldMatch';
import previewWouldReject from '@salesforce/label/c.Core_Import_PreviewWouldReject';
import resultCreated from '@salesforce/label/c.Core_Import_ResultCreated';
import resultUpdated from '@salesforce/label/c.Core_Import_ResultUpdated';
import resultMatched from '@salesforce/label/c.Core_Import_ResultMatched';
import resultRejected from '@salesforce/label/c.Core_Import_ResultRejected';
import runLogHeading from '@salesforce/label/c.Core_Import_RunLogHeading';
import rejectedHeading from '@salesforce/label/c.Core_Import_RejectedHeading';
import rowNumberHeader from '@salesforce/label/c.Core_Import_RowNumberHeader';
import reasonHeader from '@salesforce/label/c.Core_Import_ReasonHeader';
import noRejectedRows from '@salesforce/label/c.Core_Import_NoRejectedRows';
import rejectedShownOf from '@salesforce/label/c.Core_Import_RejectedShownOf';
import runningMessage from '@salesforce/label/c.Core_Import_RunningMessage';
import loadingAltText from '@salesforce/label/c.Core_Import_LoadingAltText';
import changedValuesHeading from '@salesforce/label/c.Core_Import_ChangedValuesHeading';
import columnHeader from '@salesforce/label/c.Core_Import_ColumnHeader';
import beforeHeader from '@salesforce/label/c.Core_Import_ChangesBefore';
import afterHeader from '@salesforce/label/c.Core_Import_ChangesAfter';

/**
 * What an import did, or on a dry run what it would do: the four counts, the run log, and
 * every rejected row with its reason.
 *
 * This is the screen the administrator decides on, so it never rounds, never hides a failure
 * behind a summary, and says "would" on a dry run and nothing else on a commit. It is
 * presentational: the wizard fetches and passes everything in.
 * See docs/admin-guide/importing.md.
 */
export default class ImportResults extends LightningElement {
  /** The batch view from ImportController. */
  @api batch;
  /** The rejected rows of that batch, already fetched. */
  @api rejectedRows = [];
  /** Each value a column's changes changed in the first rows, before and after (R-IT15). */
  @api changedValues = [];

  labels = {
    runLogHeading,
    rejectedHeading,
    rowNumberHeader,
    reasonHeader,
    noRejectedRows,
    runningMessage,
    loadingAltText,
    changedValuesHeading,
    columnHeader,
    beforeHeader,
    afterHeader
  };

  get hasChangedValues() {
    return Array.isArray(this.changedValues) && this.changedValues.length > 0;
  }

  get changedValueRows() {
    return (this.changedValues || []).map((changed, index) => ({
      ...changed,
      key: `changed-${index}`
    }));
  }

  get isDryRun() {
    return Boolean(this.batch && this.batch.isDryRun);
  }

  get isRunning() {
    return Boolean(this.batch && !this.batch.isFinished);
  }

  get counts() {
    const batch = this.batch || {};
    const preview = this.isDryRun;
    return [
      {
        key: 'created',
        label: preview ? previewWouldCreate : resultCreated,
        value: batch.created || 0
      },
      {
        key: 'updated',
        label: preview ? previewWouldUpdate : resultUpdated,
        value: batch.updated || 0
      },
      {
        key: 'matched',
        label: preview ? previewWouldMatch : resultMatched,
        value: batch.matched || 0
      },
      {
        key: 'rejected',
        label: preview ? previewWouldReject : resultRejected,
        value: batch.rejected || 0
      }
    ];
  }

  get hasRejectedRows() {
    return Array.isArray(this.rejectedRows) && this.rejectedRows.length > 0;
  }

  /**
   * The table shows the first page of rejected rows; when the batch has more, this says how
   * many are shown, and that the exceptions file holds them all. Empty otherwise.
   */
  get rejectedShownNote() {
    const shown = Array.isArray(this.rejectedRows) ? this.rejectedRows.length : 0;
    const total = (this.batch && this.batch.rejected) || 0;
    return shown > 0 && total > shown
      ? rejectedShownOf
          .replace('{0}', shown.toLocaleString())
          .replace('{1}', total.toLocaleString())
      : '';
  }

  get runLogLines() {
    const log = this.batch && this.batch.runLog ? this.batch.runLog : '';
    return log
      .split('\n')
      .filter((line) => line.trim().length > 0)
      .map((line, index) => ({ key: `log-${index}`, text: line }));
  }

  get hasRunLog() {
    return this.runLogLines.length > 0;
  }
}
