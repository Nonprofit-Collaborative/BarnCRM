import { LightningElement, api } from 'lwc';
import getPicklistPlan from '@salesforce/apex/FieldUtilizationController.getPicklistPlan';
import getPicklistUsage from '@salesforce/apex/FieldUtilizationController.getPicklistUsage';
import { bodyMessage } from 'c/findCsv';

import TITLE from '@salesforce/label/c.Core_PicklistUsage_Title';
import INTRO from '@salesforce/label/c.Core_PicklistUsage_Intro';
import SHOW from '@salesforce/label/c.Core_PicklistUsage_Show';
import PROGRESS from '@salesforce/label/c.Core_PicklistUsage_Progress';
import NO_FIELDS from '@salesforce/label/c.Core_PicklistUsage_NoFields';
import LAST_USED_NOTE from '@salesforce/label/c.Core_PicklistUsage_LastUsedNote';
import NOT_CHECKED from '@salesforce/label/c.Core_PicklistUsage_NotChecked';
import TRUNCATED from '@salesforce/label/c.Core_PicklistUsage_Truncated';
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
 * R-FU9 to R-FU11): for every single-select picklist field of the chosen kind of record, how
 * many records hold each value and the newest Last Modified Date among them. On demand: nothing
 * is read until the button is pressed, then one field at a time in chunks.
 */
export default class PicklistUsage extends LightningElement {
  labels = { title: TITLE, intro: INTRO, show: SHOW, noFields: NO_FIELDS, note: LAST_USED_NOTE };
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
    return this.working && this.fieldTotal > 0;
  }

  get progressValue() {
    return this.fieldTotal ? Math.round((this.fieldsDone / this.fieldTotal) * 100) : 0;
  }

  get progressText() {
    return PROGRESS.replace('{0}', this.fieldsDone).replace('{1}', this.fieldTotal);
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

  async handleShow() {
    const run = ++this.run;
    const objectName = this._objectName;
    this.rows = [];
    this.failed = [];
    this.truncated = [];
    this.fieldsDone = 0;
    this.fieldTotal = 0;
    this.errorMessage = undefined;
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
      this.fieldTotal = names.length;
      await this.loadChunk(run, objectName, names, plan.chunkSize || 20, 0);
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
  async loadChunk(run, objectName, names, size, start) {
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
    this.fieldsDone = start + fieldNames.length;
    await this.loadChunk(run, objectName, names, size, start + size);
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
