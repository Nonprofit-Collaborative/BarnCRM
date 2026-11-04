import { LightningElement, api } from 'lwc';
import getPicklistPlan from '@salesforce/apex/FieldUtilizationController.getPicklistPlan';
import getPicklistUsage from '@salesforce/apex/FieldUtilizationController.getPicklistUsage';
import getPicklistLastUsed from '@salesforce/apex/FieldUtilizationController.getPicklistLastUsed';
import { bodyMessage } from 'c/findCsv';
import { groupsOf, mergeDates, applyDates, scanProgress } from 'c/picklistUsageDates';

import TITLE from '@salesforce/label/c.Core_PicklistUsage_Title';
import SHOW from '@salesforce/label/c.Core_PicklistUsage_Show';
import PROGRESS from '@salesforce/label/c.Core_PicklistUsage_Progress';
import DATES_PROGRESS from '@salesforce/label/c.Core_PicklistUsage_DatesProgress';
import DATES_STOPPED from '@salesforce/label/c.Core_PicklistUsage_DatesStopped';
import NO_FIELDS from '@salesforce/label/c.Core_PicklistUsage_NoFields';
import NOT_CHECKED from '@salesforce/label/c.Core_PicklistUsage_NotChecked';
import TRUNCATED from '@salesforce/label/c.Core_PicklistUsage_Truncated';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import CONTINUE from '@salesforce/label/c.Core_DataManager_DeleteContinue';
import COL_FIELD from '@salesforce/label/c.Core_AccessExplorer_Field';
import COL_VALUE from '@salesforce/label/c.Core_Filter_Value';
import COL_STATUS from '@salesforce/label/c.Core_ImportRow_StatusLabel';
import COL_RECORDS from '@salesforce/label/c.Core_FieldUtilization_ColRecords';
import COL_LAST_USED from '@salesforce/label/c.Core_PicklistUsage_ColLastUsed';
import STATUS_ACTIVE from '@salesforce/label/c.Core_MatchLogic_Active';
import STATUS_INACTIVE from '@salesforce/label/c.Core_PicklistUsage_StatusInactive';
import STATUS_NEVER_USED from '@salesforce/label/c.Core_PicklistUsage_StatusNeverUsed';
import STATUS_NO_VALUE from '@salesforce/label/c.Core_PicklistUsage_StatusNoValue';
import UNEXPECTED_ERROR from '@salesforce/label/c.Core_FieldUtilization_UnexpectedError';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const STATUS_LABELS = {
  Active: STATUS_ACTIVE,
  Inactive: STATUS_INACTIVE,
  NeverUsed: STATUS_NEVER_USED,
  NoValue: STATUS_NO_VALUE
};

const WHEN = { year: 'numeric', month: 'short', day: '2-digit' };

const COLUMNS = [
  { label: COL_FIELD, fieldName: 'fieldLabel', sortable: true },
  { label: COL_VALUE, fieldName: 'valueLabel', sortable: true },
  { label: COL_STATUS, fieldName: 'statusLabel', sortable: true },
  { label: COL_RECORDS, fieldName: 'records', type: 'number', sortable: true },
  {
    label: COL_LAST_USED,
    fieldName: 'lastUsed',
    type: 'date',
    sortable: true,
    typeAttributes: WHEN
  }
];

/**
 * Picklist Value Usage, a part of the Field Utilization section (canonical model Section 29F,
 * R-FU9 to R-FU12): for every single-select picklist field of the chosen kind of record, how
 * many records hold each value and the newest Last Modified Date among them. On demand: nothing
 * is read until the button is pressed, then a chunk of fields at a time. On a large kind of
 * record the server leaves some fields' dates pending, and they are read afterwards a chunk of
 * records at a time (R-FU12), with progress, Cancel, and Continue from where a chunk stopped.
 */
export default class PicklistUsage extends LightningElement {
  helpReady = isHelpLoaded('Core');

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
  }

  labels = {
    title: TITLE,
    get intro() {
      return helpText('Core', 'Core_PicklistUsage_Intro');
    },
    show: SHOW,
    noFields: NO_FIELDS,
    get note() {
      return helpText('Core', 'Core_PicklistUsage_LastUsedNote');
    },
    cancel: CANCEL,
    retry: CONTINUE
  };
  columns = COLUMNS;
  rows = [];
  failed = [];
  truncated = [];
  fieldsDone = 0;
  fieldTotal = 0;
  working = false;
  asked = false;
  errorMessage;
  sortedBy;
  sortedDirection = 'asc';
  run = 0;
  /** The Last Used job: { objectName, groups, group, afterId, read, total, newest, cut }. */
  scan;
  scanning = false;
  scanStopped = false;
  cancelRequested = false;
  _objectName;

  @api
  get objectName() {
    return this._objectName;
  }

  set objectName(value) {
    if (value !== this._objectName) {
      this._objectName = value;
      this.run++;
      this.rows = [];
      this.failed = [];
      this.truncated = [];
      this.fieldsDone = 0;
      this.fieldTotal = 0;
      this.working = false;
      this.asked = false;
      this.errorMessage = undefined;
      this.resetScan();
    }
  }

  @api disabled = false;

  get showDisabled() {
    return this.disabled || this.working || !this._objectName;
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get showEmpty() {
    return this.asked && !this.working && this.fieldTotal === 0 && !this.errorMessage;
  }

  get showProgress() {
    return this.working && !this.scanning && this.fieldTotal > 0;
  }

  get progressValue() {
    return this.fieldTotal ? Math.round((this.fieldsDone / this.fieldTotal) * 100) : 0;
  }

  get progressText() {
    return PROGRESS.replace('{0}', this.fieldsDone).replace('{1}', this.fieldTotal);
  }

  get scanState() {
    const scan = this.scan;
    return scan
      ? scanProgress(scan.group, scan.groups.length, scan.read, scan.total)
      : { read: 0, of: 0, percent: 0 };
  }

  get datesProgressText() {
    const state = this.scanState;
    return DATES_PROGRESS.replace('{0}', state.read.toLocaleString()).replace(
      '{1}',
      state.of.toLocaleString()
    );
  }

  get showRetry() {
    return this.scanStopped && !this.working;
  }

  get datesStoppedMessage() {
    if (!this.scanStopped || !this.scan) {
      return undefined;
    }
    const state = this.scanState;
    const labelOf = new Map(this.rows.map((row) => [row.fieldName, row.fieldLabel]));
    const waiting = this.scan.groups
      .slice(this.scan.group)
      .flat()
      .map((name) => labelOf.get(name) || name);
    return DATES_STOPPED.replace('{0}', state.read.toLocaleString())
      .replace('{1}', state.of.toLocaleString())
      .replace('{2}', waiting.join(', '));
  }

  get notCheckedMessage() {
    return this.failed.length ? NOT_CHECKED.replace('{0}', this.failed.join(', ')) : undefined;
  }

  get truncatedMessage() {
    return this.truncated.length ? TRUNCATED.replace('{0}', this.truncated.join(', ')) : undefined;
  }

  get tableRows() {
    const decorated = this.rows.map((row) => ({
      ...row,
      statusLabel: STATUS_LABELS[row.status] || row.status
    }));
    return this.sortedBy ? this.sorted(decorated) : decorated;
  }

  resetScan() {
    this.scan = undefined;
    this.scanning = false;
    this.scanStopped = false;
    this.cancelRequested = false;
  }

  async handleShow() {
    const run = ++this.run;
    const objectName = this._objectName;
    this.rows = [];
    this.failed = [];
    this.truncated = [];
    this.fieldsDone = 0;
    this.fieldTotal = 0;
    this.errorMessage = undefined;
    this.resetScan();
    this.asked = true;
    this.working = true;
    try {
      const plan = await getPicklistPlan({ objectName });
      if (run !== this.run) {
        return;
      }
      if (plan.tooLarge) {
        this.fieldTotal = 0;
        return;
      }
      const names = (plan.fields || []).map((field) => field.fieldName);
      const size = plan.chunkSize || 20;
      this.fieldTotal = names.length;
      const pending = [];
      await this.loadChunk(run, objectName, names, size, 0, pending);
      if (run !== this.run || !pending.length) {
        return;
      }
      this.scan = {
        objectName,
        groups: groupsOf(pending, size),
        group: 0,
        afterId: null,
        read: 0,
        total: plan.total || 0,
        newest: {},
        cut: []
      };
      await this.readDates(run);
    } catch (error) {
      if (run === this.run) {
        this.errorMessage = bodyMessage(error, UNEXPECTED_ERROR);
      }
    } finally {
      if (run === this.run) {
        this.working = false;
      }
    }
  }

  /** One chunk of fields, then the next: one call at a time, so the server never runs two. */
  async loadChunk(run, objectName, names, size, start, pending) {
    if (start >= names.length || run !== this.run) {
      return;
    }
    const fieldNames = names.slice(start, start + size);
    const chunk = await getPicklistUsage({ objectName, fieldNames });
    if (run !== this.run) {
      return;
    }
    this.rows = [...this.rows, ...(chunk.rows || [])];
    this.failed = [...this.failed, ...(chunk.failed || [])];
    this.truncated = [...this.truncated, ...(chunk.truncated || [])];
    pending.push(...(chunk.datesPending || []));
    this.fieldsDone = start + fieldNames.length;
    await this.loadChunk(run, objectName, names, size, start + size, pending);
  }

  /**
   * Reads Last Used a chunk of records at a time for each group of pending fields (R-FU12),
   * one call at a time. A call that fails, or Cancel, stops the job where it is: what was read
   * is kept, and Continue carries on from the last chunk that finished.
   */
  async readDates(run) {
    const scan = this.scan;
    this.scanning = true;
    this.scanStopped = false;
    this.cancelRequested = false;
    try {
      while (scan.group < scan.groups.length) {
        if (this.cancelRequested) {
          this.scanStopped = true;
          return;
        }
        const fieldNames = scan.groups[scan.group];
        let chunk;
        try {
          // eslint-disable-next-line no-await-in-loop
          chunk = await getPicklistLastUsed({
            objectName: scan.objectName,
            fieldNames,
            afterId: scan.afterId
          });
        } catch {
          // The server logged it; the job stops here and Continue carries on.
          if (run === this.run) {
            this.scanStopped = true;
          }
          return;
        }
        if (run !== this.run) {
          return;
        }
        scan.newest = mergeDates(scan.newest, chunk.dates);
        scan.cut = [...scan.cut, ...(chunk.cut || [])];
        scan.read += chunk.read || 0;
        scan.afterId = chunk.lastId || scan.afterId;
        if (chunk.done) {
          this.rows = applyDates(this.rows, scan.newest, fieldNames, scan.cut);
          scan.group += 1;
          scan.afterId = null;
          scan.read = 0;
        }
        this.scan = { ...scan };
      }
    } finally {
      if (run === this.run) {
        this.scanning = false;
      }
    }
  }

  handleCancel() {
    this.cancelRequested = true;
  }

  async handleRetry() {
    if (!this.scan) {
      return;
    }
    const run = this.run;
    this.working = true;
    try {
      await this.readDates(run);
    } finally {
      if (run === this.run) {
        this.working = false;
      }
    }
  }

  handleSort(event) {
    this.sortedBy = event.detail.fieldName;
    this.sortedDirection = event.detail.sortDirection;
  }

  sorted(rows) {
    const direction = this.sortedDirection === 'desc' ? -1 : 1;
    const key = this.sortedBy;
    const valueOf = (row) => {
      const value = row[key];
      if (value === null || value === undefined) {
        return '';
      }
      return typeof value === 'string' ? value.toLowerCase() : value;
    };
    return [...rows].sort((a, b) => {
      const left = valueOf(a);
      const right = valueOf(b);
      if (left === right) {
        return 0;
      }
      return left > right ? direction : -direction;
    });
  }
}
