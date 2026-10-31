import { LightningElement, wire } from 'lwc';
import listObjects from '@salesforce/apex/FieldUtilizationController.listObjects';
import getPlan from '@salesforce/apex/FieldUtilizationController.getPlan';
import countFields from '@salesforce/apex/FieldUtilizationController.countFields';
import saveCounts from '@salesforce/apex/FieldUtilizationController.saveCounts';
import getHistory from '@salesforce/apex/FieldUtilizationController.getHistory';
import getSnapshotRows from '@salesforce/apex/FieldUtilizationController.getSnapshotRows';
import deleteSnapshotRows from '@salesforce/apex/FieldUtilizationController.deleteSnapshot';
import BarnConfirmModal from 'c/barnConfirmModal';

import TITLE from '@salesforce/label/c.Core_FieldUtilization_PageTitle';
import INTRO from '@salesforce/label/c.Core_FieldUtilization_PageIntro';
import CHOOSE_LABEL from '@salesforce/label/c.Core_FieldUtilization_ChooseLabel';
import CHOOSE_PLACEHOLDER from '@salesforce/label/c.Core_FieldUtilization_ChoosePlaceholder';
import PROGRESS from '@salesforce/label/c.Core_FieldUtilization_Progress';
import COUNT_AGAIN from '@salesforce/label/c.Core_FieldUtilization_CountAgain';
import SAVE from '@salesforce/label/c.Core_FieldUtilization_Save';
import SAVE_HELP from '@salesforce/label/c.Core_FieldUtilization_SaveHelp';
import SAVED from '@salesforce/label/c.Core_FieldUtilization_Saved';
import TOO_LARGE from '@salesforce/label/c.Core_FieldUtilization_TooLarge';
import NO_RECORDS from '@salesforce/label/c.Core_FieldUtilization_NoRecords';
import NO_FIELDS from '@salesforce/label/c.Core_FieldUtilization_NoFields';
import NOT_COUNTED from '@salesforce/label/c.Core_FieldUtilization_NotCounted';
import COMPARED_WITH from '@salesforce/label/c.Core_FieldUtilization_ComparedWith';
import NEVER_SAVED from '@salesforce/label/c.Core_FieldUtilization_NeverSaved';
import COL_FIELD from '@salesforce/label/c.Core_FieldUtilization_ColField';
import COL_API_NAME from '@salesforce/label/c.Core_FieldUtilization_ColApiName';
import COL_RECORD_TYPE from '@salesforce/label/c.Core_FieldUtilization_ColRecordType';
import COL_FILLED from '@salesforce/label/c.Core_FieldUtilization_ColFilled';
import COL_WITH_VALUE from '@salesforce/label/c.Core_FieldUtilization_ColWithValue';
import COL_RECORDS from '@salesforce/label/c.Core_FieldUtilization_ColRecords';
import COL_PREVIOUS from '@salesforce/label/c.Core_FieldUtilization_ColPrevious';
import COL_CHANGE from '@salesforce/label/c.Core_FieldUtilization_ColChange';
import COL_SAMPLED from '@salesforce/label/c.Core_FieldUtilization_ColSampled';
import UNEXPECTED_ERROR from '@salesforce/label/c.Core_FieldUtilization_UnexpectedError';
import HISTORY_TITLE from '@salesforce/label/c.Core_FieldUtilization_HistoryTitle';
import HISTORY_INTRO from '@salesforce/label/c.Core_FieldUtilization_HistoryIntro';
import HISTORY_EMPTY from '@salesforce/label/c.Core_FieldUtilization_HistoryEmpty';
import HISTORY_LIMIT from '@salesforce/label/c.Core_FieldUtilization_HistoryLimit';
import HISTORY_COL_TAKEN_AT from '@salesforce/label/c.Core_FieldUtilization_HistoryColTakenAt';
import HISTORY_COL_SAVED_BY from '@salesforce/label/c.Core_FieldUtilization_HistoryColSavedBy';
import HISTORY_COL_FIELDS from '@salesforce/label/c.Core_FieldUtilization_HistoryColFields';
import HISTORY_COL_AVERAGE from '@salesforce/label/c.Core_FieldUtilization_HistoryColAverage';
import HISTORY_COMPARE from '@salesforce/label/c.Core_FieldUtilization_HistoryCompare';
import HISTORY_VIEW from '@salesforce/label/c.Core_FieldUtilization_HistoryView';
import HISTORY_DELETE from '@salesforce/label/c.Core_FieldUtilization_HistoryDelete';
import VIEW_TITLE from '@salesforce/label/c.Core_FieldUtilization_ViewTitle';
import VIEW_CLOSE from '@salesforce/label/c.Core_FieldUtilization_ViewClose';
import VIEW_COL_OBJECT from '@salesforce/label/c.Core_FieldUtilization_ViewColObject';
import VIEW_COL_FILL_RATE from '@salesforce/label/c.Core_FieldUtilization_ViewColFillRate';
import DELETE_TITLE from '@salesforce/label/c.Core_FieldUtilization_DeleteTitle';
import DELETE_CONFIRM from '@salesforce/label/c.Core_FieldUtilization_DeleteConfirm';
import DELETE_BUTTON from '@salesforce/label/c.Core_FieldUtilization_DeleteButton';
import DELETE_CANCEL from '@salesforce/label/c.Core_FieldUtilization_DeleteCancel';
import DELETED from '@salesforce/label/c.Core_FieldUtilization_Deleted';
import { bodyMessage } from 'c/findCsv';

const PERCENT = { maximumFractionDigits: 1 };

const COLUMNS = [
  { label: COL_FIELD, fieldName: 'fieldLabel', sortable: true },
  { label: COL_API_NAME, fieldName: 'fieldName', sortable: true },
  { label: COL_RECORD_TYPE, fieldName: 'recordTypeLabel', sortable: true },
  {
    label: COL_FILLED,
    fieldName: 'share',
    type: 'percent',
    sortable: true,
    typeAttributes: PERCENT
  },
  { label: COL_WITH_VALUE, fieldName: 'filled', type: 'number', sortable: true },
  { label: COL_RECORDS, fieldName: 'total', type: 'number', sortable: true },
  {
    label: COL_PREVIOUS,
    fieldName: 'previousShare',
    type: 'percent',
    sortable: true,
    typeAttributes: PERCENT
  },
  {
    label: COL_CHANGE,
    fieldName: 'change',
    type: 'number',
    sortable: true,
    typeAttributes: PERCENT
  },
  { label: COL_SAMPLED, fieldName: 'sampled', type: 'boolean' }
];

const isBlank = (value) => value === null || value === undefined;

const HISTORY_LABELS = {
  title: HISTORY_TITLE,
  intro: HISTORY_INTRO,
  empty: HISTORY_EMPTY,
  viewClose: VIEW_CLOSE
};

const WHEN = {
  year: 'numeric',
  month: 'short',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit'
};

const VIEW_COLUMNS = [
  { label: VIEW_COL_OBJECT, fieldName: 'objectLabel' },
  { label: COL_RECORD_TYPE, fieldName: 'recordTypeLabel' },
  { label: COL_FIELD, fieldName: 'fieldLabel' },
  { label: VIEW_COL_FILL_RATE, fieldName: 'share', type: 'percent', typeAttributes: PERCENT }
];

const formatWhen = (value) => new Date(value).toLocaleString(undefined, WHEN);

/**
 * The Field Utilization tab (canonical model Section 29F, ADR-0101 field-utilization-on-demand):
 * pick a kind of record, and the page counts its fields a chunk at a time, filling the table as
 * each chunk returns. Nothing is stored until Save Utilization Snapshot. The controller checks Manage
 * BarnCRM Settings on every call.
 */
export default class FieldUtilization extends LightningElement {
  labels = {
    title: TITLE,
    intro: INTRO,
    chooseLabel: CHOOSE_LABEL,
    choosePlaceholder: CHOOSE_PLACEHOLDER,
    countAgain: COUNT_AGAIN,
    save: SAVE,
    saveHelp: SAVE_HELP,
    comparedWith: COMPARED_WITH,
    neverSaved: NEVER_SAVED,
    noRecords: NO_RECORDS,
    noFields: NO_FIELDS
  };

  columns = COLUMNS;
  objectOptions = [];
  objectName;
  plan;
  counted = [];
  rows = [];
  failed = [];
  fieldsDone = 0;
  counting = false;
  saving = false;
  sortedBy;
  sortedDirection = 'asc';
  errorMessage;
  noticeMessage;
  previousByKey = new Map();
  run = 0;
  historyLabels = HISTORY_LABELS;
  viewColumns = VIEW_COLUMNS;
  history;
  comparedAt;
  viewTakenAt;
  viewRecords = [];

  @wire(listObjects)
  wiredObjects({ data, error }) {
    if (data) {
      this.objectOptions = data;
    } else if (error) {
      this.errorMessage = bodyMessage(error, UNEXPECTED_ERROR);
    }
  }

  get fieldTotal() {
    return this.plan && this.plan.fields ? this.plan.fields.length : 0;
  }

  get progressValue() {
    return this.fieldTotal ? Math.round((this.fieldsDone / this.fieldTotal) * 100) : 0;
  }

  get progressText() {
    return PROGRESS.replace('{0}', this.fieldsDone).replace('{1}', this.fieldTotal);
  }

  get showProgress() {
    return this.fieldTotal > 0;
  }

  get tooLargeMessage() {
    if (!this.plan || !this.plan.tooLarge) {
      return undefined;
    }
    return TOO_LARGE.replace('{0}', Number(this.plan.largeObjectLimit).toLocaleString());
  }

  get hasNoRecords() {
    return !!this.plan && !this.plan.tooLarge && !this.plan.total;
  }

  get hasNoFields() {
    return !!this.plan && !this.plan.tooLarge && this.plan.total > 0 && !this.fieldTotal;
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get notCountedMessage() {
    return this.failed.length ? NOT_COUNTED.replace('{0}', this.failed.join(', ')) : undefined;
  }

  get previousTakenAt() {
    return this.comparedAt || (this.plan ? this.plan.previousTakenAt : undefined);
  }

  get showHistory() {
    return !!this.history;
  }

  get hasHistory() {
    return this.showHistory && this.history.snapshots.length > 0;
  }

  get historyLimitMessage() {
    return this.hasHistory && this.history.snapshots.length >= this.history.maxSnapshots
      ? HISTORY_LIMIT.replace('{0}', this.history.maxSnapshots)
      : undefined;
  }

  get historyRows() {
    const compared = this.previousTakenAt;
    return this.history.snapshots.map((snapshot) => ({
      key: snapshot.takenAt,
      takenAt: snapshot.takenAt,
      savedBy: snapshot.savedBy,
      rowCount: snapshot.rowCount,
      fieldCount: snapshot.fieldCount,
      averageShare: isBlank(snapshot.averagePercent) ? null : snapshot.averagePercent / 100,
      isCompared: snapshot.takenAt === compared
    }));
  }

  get historyColumns() {
    const columns = [
      { label: HISTORY_COL_TAKEN_AT, fieldName: 'takenAt', type: 'date', typeAttributes: WHEN },
      { label: HISTORY_COL_SAVED_BY, fieldName: 'savedBy' },
      { label: HISTORY_COL_FIELDS, fieldName: 'fieldCount', type: 'number' },
      {
        label: HISTORY_COL_AVERAGE,
        fieldName: 'averageShare',
        type: 'percent',
        typeAttributes: PERCENT
      },
      {
        type: 'button',
        typeAttributes: {
          label: HISTORY_COMPARE,
          name: 'compare',
          variant: 'base',
          disabled: { fieldName: 'isCompared' }
        }
      },
      {
        type: 'button',
        typeAttributes: { label: HISTORY_VIEW, name: 'view', variant: 'base' }
      }
    ];
    if (this.history && this.history.canDelete) {
      columns.push({
        type: 'button',
        typeAttributes: { label: HISTORY_DELETE, name: 'delete', variant: 'base' }
      });
    }
    return columns;
  }

  get viewTitle() {
    return this.viewTakenAt ? VIEW_TITLE.replace('{0}', formatWhen(this.viewTakenAt)) : undefined;
  }

  get viewRows() {
    const objectLabel = this.plan ? this.plan.objectLabel : '';
    return this.viewRecords.map((record) => ({
      key: record.key,
      objectLabel,
      recordTypeLabel: record.recordTypeLabel,
      fieldLabel: record.fieldLabel,
      share: isBlank(record.percent) ? null : record.percent / 100
    }));
  }

  get showNeverSaved() {
    return this.hasRows && !this.previousTakenAt;
  }

  get pickerDisabled() {
    return this.counting || this.saving;
  }

  get countAgainDisabled() {
    return !this.objectName || this.counting || this.saving;
  }

  get saveDisabled() {
    return this.counting || this.saving || !this.counted.length;
  }

  handleObject(event) {
    this.objectName = event.detail.value;
    this.count();
  }

  handleCountAgain() {
    this.count();
  }

  async count() {
    const run = ++this.run;
    const objectName = this.objectName;
    this.reset();
    if (!objectName) {
      return;
    }
    this.counting = true;
    try {
      const plan = await getPlan({ objectName });
      if (run !== this.run) {
        return;
      }
      this.applyPlan(plan);
      this.loadHistory(run, objectName);
      if (plan.tooLarge || !plan.total) {
        return;
      }
      const names = (plan.fields || []).map((field) => field.fieldName);
      await this.countChunk(run, objectName, names, plan.chunkSize || names.length || 1, 0);
    } catch (error) {
      if (run === this.run) {
        this.errorMessage = bodyMessage(error, UNEXPECTED_ERROR);
      }
    } finally {
      if (run === this.run) {
        this.counting = false;
      }
    }
  }

  /** Counts one chunk, then the next: one call at a time, so the server never runs two. */
  async countChunk(run, objectName, names, size, start) {
    if (start >= names.length || run !== this.run) {
      return;
    }
    const fieldNames = names.slice(start, start + size);
    const chunk = await countFields({ objectName, fieldNames });
    if (run !== this.run) {
      return;
    }
    this.counted = [...this.counted, ...(chunk.rows || [])];
    this.failed = [...this.failed, ...(chunk.failed || [])];
    this.fieldsDone = start + fieldNames.length;
    this.refreshRows();
    await this.countChunk(run, objectName, names, size, start + size);
  }

  async handleSave() {
    this.saving = true;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    const run = this.run;
    try {
      const rows = this.counted.map(({ fieldName, recordType, filled, total, sampled }) => ({
        fieldName,
        recordType,
        filled,
        total,
        sampled
      }));
      const saved = await saveCounts({ objectName: this.objectName, rows });
      this.noticeMessage = SAVED.replace('{0}', saved);
      const plan = await getPlan({ objectName: this.objectName });
      if (run === this.run) {
        this.applyPlan(plan);
        this.refreshRows();
        await this.loadHistory(run, this.objectName);
      }
    } catch (error) {
      this.errorMessage = bodyMessage(error, UNEXPECTED_ERROR);
    } finally {
      this.saving = false;
    }
  }

  handleSort(event) {
    this.sortedBy = event.detail.fieldName;
    this.sortedDirection = event.detail.sortDirection;
    this.refreshRows();
  }

  reset() {
    this.plan = undefined;
    this.counted = [];
    this.rows = [];
    this.failed = [];
    this.fieldsDone = 0;
    this.previousByKey = new Map();
    this.history = undefined;
    this.comparedAt = undefined;
    this.closeView();
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
  }

  applyPlan(plan) {
    this.plan = plan;
    this.comparedAt = undefined;
    this.previousByKey = new Map((plan.previous || []).map((row) => [row.key, row]));
  }

  refreshRows() {
    const decorated = this.counted.map((row) => {
      const previous = this.previousByKey.get(row.key);
      const before = previous ? previous.percent : undefined;
      return {
        ...row,
        share: isBlank(row.percent) ? null : row.percent / 100,
        previousShare: isBlank(before) ? null : before / 100,
        change:
          isBlank(before) || isBlank(row.percent)
            ? null
            : Math.round((row.percent - before) * 10) / 10
      };
    });
    this.rows = this.sortedBy ? this.sorted(decorated) : decorated;
  }

  sorted(rows) {
    const fieldName = this.sortedBy;
    const direction = this.sortedDirection === 'desc' ? -1 : 1;
    const valueOf = (row) => (isBlank(row[fieldName]) ? '' : row[fieldName]);
    return [...rows].sort((a, b) => {
      const left = valueOf(a);
      const right = valueOf(b);
      if (left === right) {
        return 0;
      }
      return left > right ? direction : -direction;
    });
  }

  /** Reads the Snapshot History list; a late answer for an earlier count is dropped. */
  async loadHistory(run, objectName) {
    try {
      const history = await getHistory({ objectName });
      if (run === this.run) {
        this.history = history;
      }
    } catch (error) {
      if (run === this.run) {
        this.errorMessage = bodyMessage(error, UNEXPECTED_ERROR);
      }
    }
  }

  async handleHistoryAction(event) {
    const { action, row } = event.detail;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    try {
      if (action.name === 'compare') {
        await this.compareWith(row.takenAt);
      } else if (action.name === 'view') {
        await this.showSnapshot(row.takenAt);
      } else if (action.name === 'delete') {
        await this.deleteSnapshot(row);
      }
    } catch (error) {
      this.errorMessage = bodyMessage(error, UNEXPECTED_ERROR);
    }
  }

  /** Makes the Saved and Change (points) columns follow the chosen snapshot. */
  async compareWith(takenAt) {
    const run = this.run;
    const rows = await getSnapshotRows({ objectName: this.objectName, takenAt });
    if (run !== this.run) {
      return;
    }
    this.previousByKey = new Map(rows.map((row) => [row.key, row]));
    this.comparedAt = takenAt;
    this.refreshRows();
  }

  async showSnapshot(takenAt) {
    const run = this.run;
    const rows = await getSnapshotRows({ objectName: this.objectName, takenAt });
    if (run === this.run) {
      this.viewRecords = rows;
      this.viewTakenAt = takenAt;
    }
  }

  async deleteSnapshot(row) {
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: DELETE_TITLE,
      message: DELETE_CONFIRM.replace('{0}', formatWhen(row.takenAt)).replace('{1}', row.rowCount),
      confirmLabel: DELETE_BUTTON,
      cancelLabel: DELETE_CANCEL,
      confirmVariant: 'destructive'
    });
    if (!confirmed) {
      return;
    }
    const run = this.run;
    const objectName = this.objectName;
    await deleteSnapshotRows({ objectName, takenAt: row.takenAt });
    if (run !== this.run) {
      return;
    }
    if (this.viewTakenAt === row.takenAt) {
      this.closeView();
    }
    this.noticeMessage = DELETED;
    // The latest saved count may be the one that went, so the comparison starts again from it.
    this.applyPlan(await getPlan({ objectName }));
    this.refreshRows();
    await this.loadHistory(run, objectName);
  }

  handleViewClose() {
    this.closeView();
  }

  closeView() {
    this.viewTakenAt = undefined;
    this.viewRecords = [];
  }
}
