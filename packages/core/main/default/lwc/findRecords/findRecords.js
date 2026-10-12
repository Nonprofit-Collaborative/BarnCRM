import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import listObjects from '@salesforce/apex/FindController.listObjects';
import listChildRelationships from '@salesforce/apex/FindController.listChildRelationships';
import saveEdits from '@salesforce/apex/FindController.saveEdits';
import getTargets from '@salesforce/apex/BulkUpdateController.getTargets';
import { CELL_TYPES, writeXlsx, xlsxFileName } from 'c/xlsxWriter';
import { valueAt } from 'c/findCsv';
import getPage from '@salesforce/apex/FindController.getPage';
import previewQuery from '@salesforce/apex/FindController.previewQuery';
import runQuery from '@salesforce/apex/FindController.runQuery';
import exportPage from '@salesforce/apex/FindController.exportPage';
import saveQuery from '@salesforce/apex/FindController.saveQuery';
import deleteQuery from '@salesforce/apex/FindController.deleteQuery';
import getObjectInfo from '@salesforce/apex/QueryFieldCatalog.getObjectInfo';
import { toCsv, fileName } from 'c/findCsv';

import TITLE from '@salesforce/label/c.Core_Find_Title';
import INTRO from '@salesforce/label/c.Core_Find_Intro';
import OBJECT from '@salesforce/label/c.Core_Find_Object';
import CHOOSE_OBJECT from '@salesforce/label/c.Core_Find_ChooseObject';
import COLUMNS from '@salesforce/label/c.Core_Find_Columns';
import AVAILABLE_FIELDS from '@salesforce/label/c.Core_Find_AvailableFields';
import CHOSEN_FIELDS from '@salesforce/label/c.Core_Find_ChosenFields';
import ADD_FIELDS_FROM from '@salesforce/label/c.Core_Find_AddFieldsFrom';
import CHOOSE_LOOKUP from '@salesforce/label/c.Core_Find_ChooseLookup';
import CONDITIONS from '@salesforce/label/c.Core_Find_Conditions';
import SORT_BY from '@salesforce/label/c.Core_Find_SortBy';
import NO_SORT from '@salesforce/label/c.Core_Find_NoSort';
import DIRECTION from '@salesforce/label/c.Core_Find_Direction';
import ASCENDING from '@salesforce/label/c.Core_Find_Ascending';
import DESCENDING from '@salesforce/label/c.Core_Find_Descending';
import ROWS_TO_SHOW from '@salesforce/label/c.Core_Find_RowsToShow';
import SOQL from '@salesforce/label/c.Core_Find_Soql';
import SOQL_HELP from '@salesforce/label/c.Core_Find_SoqlHelp';
import RUN from '@salesforce/label/c.Core_Find_Run';
import EXPORT from '@salesforce/label/c.Core_Find_Export';
import EXPORTING from '@salesforce/label/c.Core_Find_Exporting';
import EXPORT_DONE from '@salesforce/label/c.Core_Find_ExportDone';
import EXPORT_STOPPED from '@salesforce/label/c.Core_Find_ExportStopped';
import RESULT_COUNT from '@salesforce/label/c.Core_Find_ResultCount';
import RESULTS_CAPPED from '@salesforce/label/c.Core_Find_ResultsCapped';
import NO_RESULTS from '@salesforce/label/c.Core_Find_NoResults';
import SAVED_QUERIES from '@salesforce/label/c.Core_Find_SavedQueries';
import CHOOSE_SAVED from '@salesforce/label/c.Core_Find_ChooseSaved';
import SHARED_BY from '@salesforce/label/c.Core_Find_SharedBy';
import QUERY_NAME from '@salesforce/label/c.Core_Find_QueryName';
import SHARE from '@salesforce/label/c.Core_Find_Share';
import SAVE from '@salesforce/label/c.Core_Find_Save';
import SAVE_AS from '@salesforce/label/c.Core_Find_SaveAs';
import DELETE_LABEL from '@salesforce/label/c.Core_Find_Delete';
import NEW_QUERY from '@salesforce/label/c.Core_Find_New';
import SAVED_NOTICE from '@salesforce/label/c.Core_Find_SavedNotice';
import DELETED_NOTICE from '@salesforce/label/c.Core_Find_DeletedNotice';
import FIX_CONDITIONS from '@salesforce/label/c.Core_Find_FixConditions';
import CHOOSE_COLUMNS from '@salesforce/label/c.Core_Find_ChooseColumns';
import LOADING from '@salesforce/label/c.Core_Find_Loading';
import BULK_UPDATE from '@salesforce/label/c.Core_BulkUpdate_Title';
import EXPORT_EXCEL from '@salesforce/label/c.Core_Find_ExportExcel';
import SUMMARIZE from '@salesforce/label/c.Core_Find_Summarize';
import EDIT_SAVED from '@salesforce/label/c.Core_Find_EditSaved';
import EDIT_FAILED from '@salesforce/label/c.Core_Find_EditFailed';

const XLSX_TYPES = {
  currency: CELL_TYPES.NUMBER,
  double: CELL_TYPES.NUMBER,
  integer: CELL_TYPES.NUMBER,
  long: CELL_TYPES.NUMBER,
  percent: CELL_TYPES.NUMBER,
  date: CELL_TYPES.DATE,
  datetime: CELL_TYPES.DATETIME,
  boolean: CELL_TYPES.BOOLEAN
};
/** Field types lightning-datatable can edit in place (C-36, R-SQ10). */
const EDITABLE_TYPES = new Set([
  'string',
  'email',
  'phone',
  'url',
  'currency',
  'double',
  'integer',
  'percent',
  'date',
  'boolean'
]);
const TABLE_EDIT_TYPES = { email: 'email', phone: 'phone', url: 'url' };
/** The page state key a link to a saved query uses: `c__savedQueryId`, or the namespace's. */
const SAVED_QUERY_STATE = '__savedQueryId';

const DEFAULT_ROWS = 200;
const OFFERED_TYPES = new Set(['address', 'location', 'base64']);
const TABLE_TYPES = {
  currency: 'currency',
  double: 'number',
  integer: 'number',
  long: 'number',
  percent: 'number',
  date: 'date-local',
  datetime: 'date',
  boolean: 'boolean'
};

function format(template, ...values) {
  return values.reduce((text, value, index) => text.split(`{${index}}`).join(value), template);
}

/**
 * The Find tab (C-34, admin guide find.md): a visual query over one object, run, saved, shared
 * and exported with the person's own access.
 *
 * It builds the query document of canonical model R-SQ1 and never any SOQL: FindController
 * compiles the document on the server, from describe results, with every value bound, and runs
 * it in user mode. The SOQL shown is the server's display rendering. Conditions are the shared
 * filterBuilder; CSV export reads pages in Id order and writes the file in the browser (R-SQ3).
 */
export default class FindRecords extends LightningElement {
  labels = {
    title: TITLE,
    intro: INTRO,
    object: OBJECT,
    chooseObject: CHOOSE_OBJECT,
    columns: COLUMNS,
    availableFields: AVAILABLE_FIELDS,
    chosenFields: CHOSEN_FIELDS,
    addFieldsFrom: ADD_FIELDS_FROM,
    chooseLookup: CHOOSE_LOOKUP,
    conditions: CONDITIONS,
    sortBy: SORT_BY,
    direction: DIRECTION,
    rowsToShow: ROWS_TO_SHOW,
    soql: SOQL,
    soqlHelp: SOQL_HELP,
    run: RUN,
    export: EXPORT,
    exportExcel: EXPORT_EXCEL,
    summarize: SUMMARIZE,
    bulkUpdate: BULK_UPDATE,
    noResults: NO_RESULTS,
    savedQueries: SAVED_QUERIES,
    chooseSaved: CHOOSE_SAVED,
    queryName: QUERY_NAME,
    share: SHARE,
    save: SAVE,
    saveAs: SAVE_AS,
    delete: DELETE_LABEL,
    newQuery: NEW_QUERY,
    loading: LOADING
  };

  objectOptions = [];
  page;
  objectApiName;
  columns = [];
  relatedPaths = [];
  filterJson = '';
  filterValid = true;
  sortField = '';
  sortDirection = 'ASC';
  rowLimit = DEFAULT_ROWS;
  soql = '';
  rows;
  queryName = '';
  shared = false;
  openQueryId;
  bulkQueryJson;
  busy = false;
  errorMessage;
  noticeMessage;

  infoByObject = new Map();
  objectByPath = new Map();
  infoVersion = 0;
  previewSequence = 0;

  // Advanced Find (C-36): related records, the summary, and editing in the grid.
  related = [];
  children = [];
  relatedValid = true;
  aggregate;
  childLabels = {};
  editableFields = new Set();
  draftValues = [];
  tableErrors;
  requestedSavedQueryId;

  /** Another page (Data Hygiene, C-28) can link to Find with a saved query to open and run. */
  @wire(CurrentPageReference)
  handlePageReference(pageReference) {
    const state = (pageReference && pageReference.state) || {};
    const key = Object.keys(state).find((name) => name.endsWith(SAVED_QUERY_STATE));
    if (key && state[key]) {
      this.requestedSavedQueryId = state[key];
      this.openRequested();
    }
  }

  @wire(listObjects)
  wiredObjects({ data, error }) {
    if (data) {
      this.objectOptions = data.map((option) => ({ label: option.label, value: option.value }));
    } else if (error) {
      this.errorMessage = this.messageFrom(error);
    }
  }

  connectedCallback() {
    this.loadPage();
  }

  async loadPage() {
    try {
      this.page = await getPage();
    } catch (error) {
      this.errorMessage = this.messageFrom(error);
    }
    this.openRequested();
  }

  /** Opens and runs the saved query a link asked for, once the saved queries are loaded. */
  async openRequested() {
    const requested = this.requestedSavedQueryId;
    const query =
      this.page &&
      (this.page.savedQueries || []).find((candidate) => candidate.recordId === requested);
    if (!query) {
      return;
    }
    this.requestedSavedQueryId = undefined;
    await this.openSaved(query);
    await this.handleRun();
  }

  /* ---------- what the markup reads ---------- */

  get hasObject() {
    return !!this.objectApiName;
  }

  get hasError() {
    return !!this.errorMessage;
  }

  get hasNotice() {
    return !!this.noticeMessage;
  }

  get maxRows() {
    return this.page ? this.page.maxRows : 2000;
  }

  get rootInfo() {
    // infoVersion is read so the getter reruns when a describe arrives.
    return this.infoVersion >= 0 ? this.infoByObject.get(this.objectApiName) : undefined;
  }

  /** Every column that can be chosen: the object's fields, then each added related record's. */
  get fieldOptions() {
    const options = [];
    const root = this.rootInfo;
    if (!root) {
      return options;
    }
    this.offeredFields(root).forEach((field) =>
      options.push({ label: field.label, value: field.apiName })
    );
    for (const relatedPath of this.relatedPaths) {
      const info = this.infoByObject.get(this.objectByPath.get(relatedPath));
      if (info) {
        const prefix = this.pathLabel(relatedPath);
        this.offeredFields(info).forEach((field) =>
          options.push({
            label: `${prefix} > ${field.label}`,
            value: `${relatedPath}.${field.apiName}`
          })
        );
      }
    }
    return options;
  }

  /** Lookups whose fields can be added: on the object, and one more level on an added one. */
  get lookupOptions() {
    const options = [];
    const root = this.rootInfo;
    if (!root) {
      return options;
    }
    this.lookups(root).forEach((field) =>
      options.push({ label: field.label, value: field.relationshipName })
    );
    for (const relatedPath of this.relatedPaths.filter((path) => !path.includes('.'))) {
      const info = this.infoByObject.get(this.objectByPath.get(relatedPath));
      if (info) {
        this.lookups(info).forEach((field) =>
          options.push({
            label: `${this.pathLabel(relatedPath)} > ${field.label}`,
            value: `${relatedPath}.${field.relationshipName}`
          })
        );
      }
    }
    return options.filter((option) => !this.relatedPaths.includes(option.value));
  }

  get sortOptions() {
    const root = this.rootInfo;
    const fields = root ? root.fields.filter((field) => field.sortable) : [];
    return [
      { label: NO_SORT, value: '' },
      ...fields.map((field) => ({ label: field.label, value: field.apiName }))
    ];
  }

  get directionOptions() {
    return [
      { label: ASCENDING, value: 'ASC' },
      { label: DESCENDING, value: 'DESC' }
    ];
  }

  get savedOptions() {
    const queries = this.page && this.page.savedQueries ? this.page.savedQueries : [];
    return queries.map((query) => ({
      label: query.mine ? query.name : format(SHARED_BY, query.name, query.ownerName),
      value: query.recordId
    }));
  }

  get openQuery() {
    const queries = this.page && this.page.savedQueries ? this.page.savedQueries : [];
    return queries.find((query) => query.recordId === this.openQueryId);
  }

  get canSave() {
    return this.hasObject && !this.busy && (!this.openQuery || this.openQuery.mine);
  }

  get saveDisabled() {
    return !this.canSave;
  }

  get deleteDisabled() {
    return this.busy || !this.openQuery || !this.openQuery.mine;
  }

  get actionDisabled() {
    return this.busy || !this.hasObject;
  }

  get tableColumns() {
    return this.outputColumns().map((column) => {
      const dataType = column.field?.dataType;
      const shown = {
        label: column.label,
        fieldName: column.key,
        type: TABLE_EDIT_TYPES[dataType] || TABLE_TYPES[dataType] || 'text'
      };
      if (this.editableFields.has(column.key)) {
        shown.editable = true;
      }
      return shown;
    });
  }

  get tableRows() {
    return (this.rows || []).map((row) => {
      const flat = { Id: row.Id };
      for (const column of this.outputColumns()) {
        flat[column.key] = column.valueOf(row);
      }
      return flat;
    });
  }

  /**
   * Every column the grid and the exports show: the chosen fields, then each related record
   * column as text such as "Ana Ruiz, ana@example.org; Ben Ruiz, ben@example.org".
   */
  outputColumns() {
    const fields = this.columns.map((path) => ({
      key: path,
      label: this.columnLabel(path),
      field: this.fieldOf(path),
      valueOf: (row) => valueAt(row, path)
    }));
    const related = this.children.map((child) => ({
      key: child.relationship,
      label: this.childLabels[child.relationship] || child.relationship,
      field: undefined,
      valueOf: (row) => {
        const records = row[child.relationship];
        const list = Array.isArray(records) ? records : (records && records.records) || [];
        return list
          .map((record) =>
            child.fields
              .map((path) => valueAt(record, path))
              .filter((value) => value !== undefined && value !== null && value !== '')
              .join(', ')
          )
          .join('; ');
      }
    }));
    return [...fields, ...related];
  }

  /** The query as the summary panel reads it: the document without its summary. */
  get summaryQueryJson() {
    return this.hasObject && this.columns.length > 0 ? this.queryDocument(false) : '';
  }

  get hasRows() {
    return !!this.rows && this.rows.length > 0;
  }

  get canBulkUpdate() {
    return Boolean(this.page && this.page.canBulkUpdate);
  }

  get showBulkUpdate() {
    return Boolean(this.bulkQueryJson);
  }

  get showNoResults() {
    return !!this.rows && this.rows.length === 0;
  }

  get resultLine() {
    if (!this.rows) {
      return '';
    }
    const count = String(this.rows.length);
    return this.rows.length >= Number(this.rowLimit)
      ? format(RESULTS_CAPPED, count)
      : format(RESULT_COUNT, count);
  }

  /* ---------- the query document ---------- */

  queryDocument(withSummary = true) {
    const document = {
      version: 1,
      object: this.objectApiName,
      fields: [...this.columns],
      limit: Number(this.rowLimit)
    };
    if (this.filterJson) {
      document.filter = JSON.parse(this.filterJson);
    }
    if (this.sortField) {
      document.orderBy = [{ field: this.sortField, direction: this.sortDirection }];
    }
    if (this.related.length > 0) {
      document.related = this.related;
    }
    if (this.children.length > 0) {
      document.children = this.children;
    }
    if (withSummary && this.aggregate) {
      document.aggregate = this.aggregate;
    }
    return JSON.stringify(document);
  }

  /** Says what to fix before anything is sent, or returns true. */
  checkReady() {
    if (this.columns.length === 0) {
      this.errorMessage = CHOOSE_COLUMNS;
      return false;
    }
    const builder = this.template.querySelector('c-filter-builder');
    if (!this.filterValid || !this.relatedValid || (builder && !builder.reportValidity())) {
      this.errorMessage = FIX_CONDITIONS;
      return false;
    }
    return true;
  }

  async refreshPreview() {
    // The bulk update panel acts on the query it was opened with; an edited query closes it.
    this.bulkQueryJson = undefined;
    if (
      !this.objectApiName ||
      this.columns.length === 0 ||
      !this.filterValid ||
      !this.relatedValid
    ) {
      this.soql = '';
      return;
    }
    const sequence = ++this.previewSequence;
    try {
      const soql = await previewQuery({ queryJson: this.queryDocument() });
      if (sequence === this.previewSequence) {
        this.soql = soql;
        this.errorMessage = undefined;
      }
    } catch (error) {
      if (sequence === this.previewSequence) {
        this.soql = '';
        this.errorMessage = this.messageFrom(error);
      }
    }
  }

  /* ---------- events ---------- */

  async handleObjectChange(event) {
    this.resetQuery();
    this.objectApiName = event.detail.value;
    await this.loadInfo(this.objectApiName);
    this.columns = this.defaultColumns();
    this.loadEditable();
    this.refreshPreview();
  }

  handleRelatedChange(event) {
    this.related = event.detail.related;
    this.children = event.detail.children;
    this.relatedValid = event.detail.valid;
    this.loadChildLabels();
    this.refreshPreview();
  }

  handleSummaryChange(event) {
    this.aggregate = event.detail.aggregate;
  }

  /** A typed query, read into a document by findQueryTextPanel (R-SQ7), loads like a saved one. */
  async handleTypedQuery(event) {
    this.noticeMessage = undefined;
    const keep = { openQueryId: this.openQueryId, queryName: this.queryName, shared: this.shared };
    await this.work(async () => {
      await this.loadDocument(event.detail.document);
      Object.assign(this, keep);
    });
    this.refreshPreview();
  }

  handleCellChange(event) {
    const byId = new Map(this.draftValues.map((draft) => [draft.Id, draft]));
    for (const draft of event.detail.draftValues) {
      byId.set(draft.Id, { ...(byId.get(draft.Id) || {}), ...draft });
    }
    this.draftValues = [...byId.values()];
  }

  handleCancelEdits() {
    this.draftValues = [];
    this.tableErrors = undefined;
  }

  /** Saves the grid's edits as the person, journaled and undoable (C-36, R-SQ10). */
  async handleSaveEdits(event) {
    const drafts = event.detail.draftValues;
    this.noticeMessage = undefined;
    await this.work(async () => {
      const summary = await saveEdits({
        objectApiName: this.objectApiName,
        editsJson: JSON.stringify(drafts)
      });
      const result = await runQuery({ queryJson: this.queryDocument() });
      this.rows = result.rows;
      const failed = new Set(summary.errors.map((error) => error.recordId));
      this.draftValues = drafts.filter((draft) => failed.has(draft.Id));
      this.tableErrors = failed.size === 0 ? undefined : this.errorsFor(summary.errors, drafts);
      this.noticeMessage = format(EDIT_SAVED, String(summary.saved), String(summary.unchanged));
    });
  }

  errorsFor(errors, drafts) {
    const rows = {};
    for (const error of errors) {
      const draft = drafts.find((candidate) => candidate.Id === error.recordId) || {};
      rows[error.recordId] = {
        title: EDIT_FAILED.split('{0}').join('1'),
        messages: [error.message],
        fieldNames: Object.keys(draft).filter((name) => name !== 'Id')
      };
    }
    return {
      rows,
      table: { title: EDIT_FAILED.split('{0}').join(String(errors.length)), messages: [] }
    };
  }

  /** The fields the person may edit in the grid: the object's own that bulk update may write. */
  async loadEditable() {
    this.editableFields = new Set();
    if (!this.canBulkUpdate || !this.objectApiName) {
      return;
    }
    // An object bulk update cannot write is simply not editable in the grid.
    const targets = (await getTargets({ objectName: this.objectApiName }).catch(() => [])) || [];
    this.editableFields = new Set(
      targets.filter((target) => EDITABLE_TYPES.has(target.dataType)).map((t) => t.apiName)
    );
  }

  async loadChildLabels() {
    if (this.children.length === 0 || this.childLabels.loadedFor === this.objectApiName) {
      return;
    }
    // Without the labels, a related record column is headed by its relationship name.
    const options =
      (await listChildRelationships({ objectApiName: this.objectApiName }).catch(() => [])) || [];
    const labels = { loadedFor: this.objectApiName };
    options.forEach((option) => {
      labels[option.relationshipName] = option.label;
    });
    this.childLabels = labels;
  }

  handleColumnsChange(event) {
    this.columns = [...event.detail.value];
    this.refreshPreview();
  }

  async handleAddRelated(event) {
    const path = event.detail.value;
    await this.addRelated(path);
  }

  handleFilterChange(event) {
    this.filterJson = event.detail.value;
    this.filterValid = event.detail.valid;
    this.refreshPreview();
  }

  handleSortChange(event) {
    this.sortField = event.detail.value;
    this.refreshPreview();
  }

  handleDirectionChange(event) {
    this.sortDirection = event.detail.value;
    this.refreshPreview();
  }

  handleRowLimitChange(event) {
    this.rowLimit = event.target.value;
    this.refreshPreview();
  }

  handleNameChange(event) {
    this.queryName = event.target.value;
  }

  handleShareChange(event) {
    this.shared = event.target.checked;
  }

  async handleRun() {
    this.noticeMessage = undefined;
    if (!this.checkReady()) {
      return;
    }
    await this.work(async () => {
      const result = await runQuery({ queryJson: this.queryDocument() });
      this.soql = result.soql;
      this.rows = result.rows;
      this.draftValues = [];
      this.tableErrors = undefined;
    });
  }

  handleExport() {
    return this.exportAs('csv');
  }

  handleExportExcel() {
    return this.exportAs('xlsx');
  }

  /** Reads every page (R-SQ3) and writes CSV, or an Excel workbook (R-SQ11). */
  async exportAs(kind) {
    this.noticeMessage = undefined;
    if (!this.checkReady()) {
      return;
    }
    await this.work(async () => {
      const limit = this.page ? this.page.exportLimit : 50000;
      const queryJson = this.queryDocument();
      let rows = [];
      let afterId = null;
      let done = false;
      while (!done && rows.length < limit) {
        // Each page starts after the last Id of the one before, so pages are read in turn.
        // eslint-disable-next-line no-await-in-loop
        const result = await exportPage({ queryJson, afterId });
        rows = rows.concat(result.rows);
        afterId = result.lastId;
        done = result.done;
        this.noticeMessage = format(EXPORTING, String(rows.length));
      }
      const stopped = rows.length >= limit && !done;
      rows = rows.slice(0, limit);
      const columns = this.outputColumns();
      if (kind === 'xlsx') {
        const bytes = await writeXlsx(
          columns.map((column) => ({
            label: column.label,
            type: XLSX_TYPES[column.field?.dataType] || CELL_TYPES.TEXT
          })),
          rows.map((row) => columns.map((column) => column.valueOf(row))),
          { sheetName: this.objectApiName }
        );
        this.download(
          new Blob([bytes], {
            type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
          }),
          xlsxFileName(this.objectApiName)
        );
      } else {
        // Each row as an array, so a column's path is its position.
        const flat = rows.map((row) => columns.map((column) => column.valueOf(row)));
        this.download(
          new Blob(
            [
              toCsv(
                columns.map((column, index) => ({ label: column.label, path: String(index) })),
                flat
              )
            ],
            { type: 'text/csv;charset=utf-8' }
          ),
          fileName(this.objectApiName)
        );
      }
      this.noticeMessage = stopped
        ? format(EXPORT_STOPPED, String(limit))
        : format(EXPORT_DONE, String(rows.length));
    });
  }

  handleSave() {
    return this.save(this.openQuery && this.openQuery.mine ? this.openQueryId : null);
  }

  handleSaveAs() {
    return this.save(null);
  }

  async save(recordId) {
    this.noticeMessage = undefined;
    if (!this.checkReady()) {
      return;
    }
    await this.work(async () => {
      this.page = await saveQuery({
        recordId,
        name: this.queryName,
        queryJson: this.queryDocument(),
        shared: this.shared
      });
      const saved = this.page.savedQueries.find(
        (query) => query.mine && query.name === this.queryName.trim()
      );
      this.openQueryId = saved ? saved.recordId : this.openQueryId;
      this.noticeMessage = format(SAVED_NOTICE, this.queryName.trim());
    });
  }

  async handleDelete() {
    const name = this.openQuery ? this.openQuery.name : '';
    await this.work(async () => {
      this.page = await deleteQuery({ recordId: this.openQueryId });
      this.resetQuery();
      this.objectApiName = undefined;
      this.noticeMessage = format(DELETED_NOTICE, name);
    });
  }

  /** Opens bulk update over the query as it is now (C-35); the panel keeps that query. */
  handleBulkUpdate() {
    this.noticeMessage = undefined;
    this.errorMessage = undefined;
    if (!this.checkReady()) {
      return;
    }
    this.bulkQueryJson = this.queryDocument();
  }

  handleBulkClose() {
    this.bulkQueryJson = undefined;
  }

  handleNew() {
    this.resetQuery();
    this.objectApiName = undefined;
    this.noticeMessage = undefined;
    this.errorMessage = undefined;
  }

  async handleOpenSaved(event) {
    const query = (this.page.savedQueries || []).find(
      (candidate) => candidate.recordId === event.detail.value
    );
    if (!query) {
      return;
    }
    await this.openSaved(query);
  }

  async openSaved(query) {
    await this.work(async () => {
      await this.loadDocument(JSON.parse(query.queryJson));
      this.openQueryId = query.recordId;
      this.queryName = query.name;
      this.shared = query.shared === true;
    });
    this.refreshPreview();
  }

  /** Loads a query document into the builder: a saved query's, or a typed one's. */
  async loadDocument(document) {
    this.resetQuery();
    this.objectApiName = document.object;
    await this.loadInfo(this.objectApiName);
    for (const path of document.fields || []) {
      const segments = path.split('.');
      for (let depth = 1; depth < segments.length; depth++) {
        // A related path needs the one before it described first.
        // eslint-disable-next-line no-await-in-loop
        await this.addRelated(segments.slice(0, depth).join('.'));
      }
    }
    this.columns = [...(document.fields || [])];
    this.filterJson = document.filter ? JSON.stringify(document.filter) : '';
    const order = (document.orderBy || [])[0];
    this.sortField = order ? order.field : '';
    this.sortDirection = order ? order.direction : 'ASC';
    this.rowLimit = document.limit || DEFAULT_ROWS;
    this.related = document.related || [];
    this.children = document.children || [];
    this.aggregate = document.aggregate;
    this.loadChildLabels();
    this.loadEditable();
  }

  /* ---------- helpers ---------- */

  resetQuery() {
    this.columns = [];
    this.relatedPaths = [];
    this.objectByPath = new Map();
    this.filterJson = '';
    this.filterValid = true;
    this.sortField = '';
    this.sortDirection = 'ASC';
    this.rowLimit = DEFAULT_ROWS;
    this.rows = undefined;
    this.soql = '';
    this.openQueryId = undefined;
    this.queryName = '';
    this.shared = false;
    this.bulkQueryJson = undefined;
    this.related = [];
    this.children = [];
    this.relatedValid = true;
    this.aggregate = undefined;
    this.draftValues = [];
    this.tableErrors = undefined;
  }

  async work(action) {
    this.busy = true;
    this.errorMessage = undefined;
    try {
      await action();
    } catch (error) {
      this.errorMessage = this.messageFrom(error);
    } finally {
      this.busy = false;
    }
  }

  async loadInfo(objectApiName) {
    if (!this.infoByObject.has(objectApiName)) {
      this.infoByObject.set(objectApiName, await getObjectInfo({ objectApiName }));
      this.infoVersion++;
    }
    return this.infoByObject.get(objectApiName);
  }

  /** Adds a related record (`Donor_Contact__r` or `Donor_Contact__r.Account`) to the column list. */
  async addRelated(path) {
    if (this.relatedPaths.includes(path)) {
      return;
    }
    const segments = path.split('.');
    const parentObject =
      segments.length === 1
        ? this.objectApiName
        : this.objectByPath.get(segments.slice(0, -1).join('.'));
    const parentInfo = this.infoByObject.get(parentObject);
    const lookup = parentInfo
      ? parentInfo.fields.find((field) => field.relationshipName === segments[segments.length - 1])
      : undefined;
    if (!lookup) {
      return;
    }
    this.objectByPath.set(path, lookup.referenceTo);
    await this.loadInfo(lookup.referenceTo);
    this.relatedPaths = [...this.relatedPaths, path];
  }

  offeredFields(info) {
    return info.fields.filter((field) => !OFFERED_TYPES.has(field.dataType));
  }

  lookups(info) {
    return info.fields.filter((field) => field.referenceTo && field.relationshipName);
  }

  defaultColumns() {
    const root = this.rootInfo;
    if (!root) {
      return [];
    }
    const name = root.fields.find((field) => field.apiName === 'Name');
    return name ? ['Name'] : [];
  }

  /** The field a column path ends on, from the describes already loaded. */
  fieldOf(path) {
    const segments = path.split('.');
    const objectName =
      segments.length === 1
        ? this.objectApiName
        : this.objectByPath.get(segments.slice(0, -1).join('.'));
    const info = this.infoByObject.get(objectName);
    return info
      ? info.fields.find((field) => field.apiName === segments[segments.length - 1])
      : undefined;
  }

  /** `Donor > Account`, from the lookups a related path crosses. */
  pathLabel(relatedPath) {
    const segments = relatedPath.split('.');
    const labels = [];
    let objectName = this.objectApiName;
    for (let depth = 0; depth < segments.length; depth++) {
      const info = this.infoByObject.get(objectName);
      const lookup = info
        ? info.fields.find((field) => field.relationshipName === segments[depth])
        : undefined;
      labels.push(lookup ? lookup.label : segments[depth]);
      objectName = this.objectByPath.get(segments.slice(0, depth + 1).join('.'));
    }
    return labels.join(' > ');
  }

  columnLabel(path) {
    const field = this.fieldOf(path);
    const leaf = field ? field.label : path;
    return path.includes('.')
      ? `${this.pathLabel(path.split('.').slice(0, -1).join('.'))} > ${leaf}`
      : leaf;
  }

  download(blob, name) {
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = name;
    link.click();
    URL.revokeObjectURL(link.href);
  }

  messageFrom(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    return error && error.message ? error.message : String(error);
  }
}
