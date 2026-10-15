import { LightningElement, api } from 'lwc';
import getAttention from '@salesforce/apex/RollupAttentionController.getAttention';
import retry from '@salesforce/apex/RollupAttentionController.retry';
import processNow from '@salesforce/apex/RollupAttentionController.processNow';

import TITLE from '@salesforce/label/c.Core_RollupBuilder_AttentionTitle';
import FAILED_TITLE from '@salesforce/label/c.Core_RollupBuilder_FailedTitle';
import NOTHING_FAILED from '@salesforce/label/c.Core_RollupBuilder_NothingFailed';
import COLUMN_RECORD from '@salesforce/label/c.Core_RollupBuilder_ColumnRecord';
import COLUMN_ERROR from '@salesforce/label/c.Core_RollupBuilder_ColumnError';
import COLUMN_WHEN from '@salesforce/label/c.Core_RollupBuilder_ColumnWhen';
import COLUMN_TRIES from '@salesforce/label/c.Core_RollupBuilder_ColumnTries';
import RETRY from '@salesforce/label/c.Core_RollupBuilder_Retry';
import RETRY_ALL from '@salesforce/label/c.Core_RollupBuilder_RetryAll';
import RETRIED from '@salesforce/label/c.Core_RollupBuilder_Retried';
import NIGHTLY_OFF from '@salesforce/label/c.Core_RollupBuilder_NightlyOff';
import START_NOW from '@salesforce/label/c.Core_RollupBuilder_StartNow';
import STARTED from '@salesforce/label/c.Core_RollupBuilder_Started';
import UNEXPECTED_ERROR from '@salesforce/label/c.Core_Rollups_UnexpectedError';

/**
 * Needs attention in the Rollup Builder (rollup proposal slice S13, canonical model Section 14A):
 * how many records wait in the queue with Start now, each record whose totals could not be saved
 * with what went wrong, Retry for the selected ones or all, a warning when the nightly run is
 * off, and how the last full run ended.
 */
export default class RollupNeedsAttention extends LightningElement {
  labels = {
    title: TITLE,
    failedTitle: FAILED_TITLE,
    nothingFailed: NOTHING_FAILED,
    retry: RETRY,
    retryAll: RETRY_ALL,
    nightlyOff: NIGHTLY_OFF,
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
  get shown() {
    return !!this.error || (!!this.attention && this.attention.canManage === true);
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
        this.notice = STARTED;
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
        this.notice = RETRIED;
        this.error = undefined;
      })
      .catch((error) => this.fail(error))
      .finally(() => {
        this.busy = false;
      });
  }

  fail(error) {
    this.error = error && error.body && error.body.message ? error.body.message : UNEXPECTED_ERROR;
  }
}
