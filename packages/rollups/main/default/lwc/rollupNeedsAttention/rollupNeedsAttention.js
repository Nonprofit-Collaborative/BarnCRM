import { LightningElement, api } from 'lwc';
import getAttention from '@salesforce/apex/RollupAttentionController.getAttention';
import retry from '@salesforce/apex/RollupAttentionController.retry';
import processNow from '@salesforce/apex/RollupAttentionController.processNow';

import TITLE from '@salesforce/label/c.Core_DataHygiene_NeedsAttention';
import FAILED_TITLE from '@salesforce/label/c.Rollups_RollupBuilder_FailedTitle';
import COLUMN_RECORD from '@salesforce/label/c.Core_BulkUpdate_Record';
import COLUMN_ERROR from '@salesforce/label/c.Rollups_RollupBuilder_ColumnError';
import COLUMN_WHEN from '@salesforce/label/c.Core_FieldAccess_ColWhen';
import COLUMN_TRIES from '@salesforce/label/c.Rollups_RollupBuilder_ColumnTries';
import RETRY from '@salesforce/label/c.Rollups_RollupBuilder_Retry';
import RETRY_ALL from '@salesforce/label/c.Rollups_RollupBuilder_RetryAll';
import START_NOW from '@salesforce/label/c.Rollups_RollupBuilder_StartNow';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

/**
 * Needs attention in the Rollup Builder (rollup proposal slice S13, canonical model Section 14A):
 * how many records wait in the queue with Start now, each record whose totals could not be saved
 * with what went wrong, Retry for the selected ones or all, a warning when the nightly run is
 * off, and how the last full run ended.
 */
export default class RollupNeedsAttention extends LightningElement {
  helpReady = isHelpLoaded('Rollups');

  labels = {
    title: TITLE,
    failedTitle: FAILED_TITLE,
    get nothingFailed() {
      return helpText('Rollups', 'Core_RollupBuilder_NothingFailed');
    },
    retry: RETRY,
    retryAll: RETRY_ALL,
    get nightlyOff() {
      return helpText('Rollups', 'Core_RollupBuilder_NightlyOff');
    },
    startNow: START_NOW
  };

  columns = [
    {
      label: COLUMN_RECORD,
      fieldName: 'link',
      type: 'url',
      typeAttributes: { label: { fieldName: 'name' }, target: '_self' }
    },
    { label: COLUMN_ERROR, fieldName: 'error', wrapText: true },
    { label: COLUMN_WHEN, fieldName: 'failedAt', type: 'date' },
    { label: COLUMN_TRIES, fieldName: 'attempts', type: 'number' }
  ];

  attention;
  selectedEntryIds = [];
  error;
  notice;
  busy = false;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Rollups').then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  /** Reads the list again, for the Builder after a save or a recalculation. */
  @api
  load() {
    return getAttention()
      .then((attention) => {
        this.attention = attention;
        this.error = undefined;
      })
      .catch((error) => this.fail(error));
  }

  get rows() {
    return ((this.attention && this.attention.failed) || []).map((row) => ({
      ...row,
      link: `/${row.recordId}`
    }));
  }

  get hasFailed() {
    return this.rows.length > 0;
  }

  /**
   * Shown to someone who can act on it, or with the error a load ended in. Staff and Read Only
   * see the Builder without it: the queue is not read for them (RollupAttentionController).
   */
  // Reads helpReady so the section renders again once the help text (nightlyOff, nothingFailed)
  // has loaded: those getters on the plain labels object are not reactive themselves.
  get shown() {
    return (
      this.helpReady && (!!this.error || !!this.notice || (this.canManageList && this.hasItems))
    );
  }

  get canManageList() {
    return !!this.attention && this.attention.canManage === true;
  }

  /** The list opens only when something needs attention (pg-21); a clean queue shows nothing. */
  get hasItems() {
    return (
      this.hasFailed ||
      this.showNightlyOff ||
      (!!this.attention && this.attention.hasWaiting === true)
    );
  }

  /** What the count badge counts: failed records, the waiting queue, and a missing nightly run. */
  get itemCount() {
    return (
      this.rows.length +
      (this.attention && this.attention.hasWaiting === true ? 1 : 0) +
      (this.showNightlyOff ? 1 : 0)
    );
  }

  get hasCount() {
    return this.canManageList && this.itemCount > 0;
  }

  get itemCountText() {
    return String(this.itemCount);
  }

  get failedCount() {
    return this.rows.length;
  }

  get showNightlyOff() {
    return !!this.attention && this.attention.nightlyScheduled === false;
  }

  get canRetry() {
    return !!this.attention && this.attention.canManage === true && this.hasFailed;
  }

  get canStart() {
    return (
      !!this.attention && this.attention.canManage === true && this.attention.hasWaiting === true
    );
  }

  handleStartNow() {
    this.busy = true;
    this.notice = undefined;
    processNow()
      .then((attention) => {
        this.attention = attention;
        this.notice = helpText('Rollups', 'Core_RollupBuilder_Started');
        this.error = undefined;
      })
      .catch((error) => this.fail(error))
      .finally(() => {
        this.busy = false;
      });
  }

  get hideCheckboxes() {
    return !this.canRetry;
  }

  get retryDisabled() {
    return this.busy || this.selectedEntryIds.length === 0;
  }

  handleSelection(event) {
    const ids = new Set(event.detail.selectedRows.map((row) => row.entryId));
    this.selectedEntryIds = [...ids];
  }

  handleRetry() {
    this.runRetry(this.selectedEntryIds);
  }

  handleRetryAll() {
    this.runRetry(null);
  }

  runRetry(entryIds) {
    this.busy = true;
    this.notice = undefined;
    retry({ entryIds })
      .then((attention) => {
        this.attention = attention;
        this.selectedEntryIds = [];
        this.notice = helpText('Rollups', 'Core_RollupBuilder_Retried');
        this.error = undefined;
      })
      .catch((error) => this.fail(error))
      .finally(() => {
        this.busy = false;
      });
  }

  fail(error) {
    this.error =
      error && error.body && error.body.message
        ? error.body.message
        : helpText('Rollups', 'Core_Rollups_UnexpectedError');
  }
}
