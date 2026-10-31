import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { EnclosingTabId } from 'lightning/platformWorkspaceApi';
import { labelTab } from 'c/workspaceTabs';
import BarnConfirmModal from 'c/barnConfirmModal';
import listObjects from '@salesforce/apex/FindController.listObjects';
import listChildRelationships from '@salesforce/apex/FindController.listChildRelationships';
import saveEdits from '@salesforce/apex/FindController.saveEdits';
import getTargets from '@salesforce/apex/BulkUpdateController.getTargets';
import { CELL_TYPES, writeXlsx } from 'c/xlsxWriter';
import { fileName, format, messageFrom, toCsv, valueAt, zonedDateTime } from 'c/findCsv';
import TIME_ZONE from '@salesforce/i18n/timeZone';
import getPage from '@salesforce/apex/FindController.getPage';
import previewQuery from '@salesforce/apex/FindController.previewQuery';
import runQuery from '@salesforce/apex/FindController.runQuery';
import exportPage from '@salesforce/apex/FindController.exportPage';
import saveQuery from '@salesforce/apex/FindController.saveQuery';
import deleteQuery from '@salesforce/apex/FindController.deleteQuery';
import getObjectInfo from '@salesforce/apex/QueryFieldCatalog.getObjectInfo';

import TITLE from '@salesforce/label/c.Core_Find_Title';
import TAB_LABEL from '@salesforce/label/c.Core_Console_TabLabel';
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
import DELETE_CONFIRM_HEADING from '@salesforce/label/c.Core_Find_DeleteConfirmHeading';
import DELETE_CONFIRM_BODY from '@salesforce/label/c.Core_Find_DeleteConfirmBody';
import DELETE_CONFIRM_SHARED from '@salesforce/label/c.Core_Find_DeleteConfirmShared';
import DELETE_CONFIRM_CANCEL from '@salesforce/label/c.Core_Find_DeleteConfirmCancel';
import DELETED_NOTICE from '@salesforce/label/c.Core_Find_DeletedNotice';
import FIX_CONDITIONS from '@salesforce/label/c.Core_Find_FixConditions';
import CHOOSE_COLUMNS from '@salesforce/label/c.Core_Find_ChooseColumns';
import LOADING from '@salesforce/label/c.Core_Find_Loading';
import BULK_UPDATE from '@salesforce/label/c.Core_BulkUpdate_Title';
import BULK_DELETE from '@salesforce/label/c.Core_BulkDelete_Title';
import EXPORT_EXCEL from '@salesforce/label/c.Core_Find_ExportExcel';
import EXPORT_FILES from '@salesforce/label/c.Core_Find_ExportFiles';
import SUMMARIZE from '@salesforce/label/c.Core_Find_Summarize';
import EDIT_SAVED from '@salesforce/label/c.Core_Find_EditSaved';
import EDIT_FAILED from '@salesforce/label/c.Core_Find_EditFailed';
import HIDDEN_COLUMNS from '@salesforce/label/c.Core_Find_HiddenColumns';
import PURPOSE from '@salesforce/label/c.Core_Find_Purpose';
import GUIDE_URL from '@salesforce/label/c.Core_Find_GuideUrl';
import EMPTY_HEADING from '@salesforce/label/c.Core_Find_EmptyHeading';
import EMPTY_MESSAGE from '@salesforce/label/c.Core_Find_EmptyMessage';
import NO_RESULTS_HEADING from '@salesforce/label/c.Core_Find_NoResultsHeading';
import SHOW_QUERY from '@salesforce/label/c.Core_Find_ShowQuery';
import RESULTS from '@salesforce/label/c.Core_Find_Results';
import SHOW_MORE from '@salesforce/label/c.Core_Find_ShowMore';
import SHOWING_OF from '@salesforce/label/c.Core_Find_ShowingOf';
import EXPORT_MENU from '@salesforce/label/c.Core_Find_ExportMenu';
import CHANGE_RECORDS from '@salesforce/label/c.Core_Find_ChangeRecords';
import SAVE_HEADING from '@salesforce/label/c.Core_Find_SaveHeading';
import MORE_QUERY_ACTIONS from '@salesforce/label/c.Core_Find_MoreQueryActions';
import START_UPDATE from '@salesforce/label/c.Core_Find_StartUpdate';
import START_DELETE from '@salesforce/label/c.Core_Find_StartDelete';

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
/** The state key the Data Manager's bulk cards use, matched by suffix: "update" or "delete" (D-135). */
const TOOL_STATE = '__tool';
/** The state key the Record Inspector (C-55) uses to open Find on one object: `c__object`. */
const OBJECT_STATE = '__object';
const START_NOTES = { update: START_UPDATE, delete: START_DELETE };

const DEFAULT_ROWS = 200;
/** Rows the table shows at first and adds on each Show More; exports never use it. */
const PAGE_SIZE = 25;
/** How long typing must pause before the SOQL preview asks the server (FINDA-4). */
const PREVIEW_DEBOUNCE_MS = 300;
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
/**
 * A date-time column shows its time too, in the person's Salesforce time zone: the same clock
 * the CSV and the workbook write.
 */
const DATETIME_ATTRIBUTES = {
  year: 'numeric',
  month: 'short',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  timeZone: TIME_ZONE
};

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
    exportFiles: EXPORT_FILES,
    summarize: SUMMARIZE,
    bulkUpdate: BULK_UPDATE,
    bulkDelete: BULK_DELETE,
    noResults: NO_RESULTS,
    savedQueries: SAVED_QUERIES,
    chooseSaved: CHOOSE_SAVED,
    queryName: QUERY_NAME,
    share: SHARE,
    save: SAVE,
    saveAs: SAVE_AS,
    delete: DELETE_LABEL,
    newQuery: NEW_QUERY,
    loading: LOADING,
    purpose: PURPOSE,
    guideUrl: GUIDE_URL,
    emptyHeading: EMPTY_HEADING,
    emptyMessage: EMPTY_MESSAGE,
    noResultsHeading: NO_RESULTS_HEADING,
    showQuery: SHOW_QUERY,
    results: RESULTS,
    showMore: SHOW_MORE,
    exportMenu: EXPORT_MENU,
    changeRecords: CHANGE_RECORDS,
    saveHeading: SAVE_HEADING,
    moreQueryActions: MORE_QUERY_ACTIONS
  };

  /** Show Query starts closed: the SOQL is for checking, not for every visit. */
  closedSections = [];
  /** How many result rows the table shows; Show More adds PAGE_SIZE. */
  shownCount = PAGE_SIZE;
  /** The note Find shows when a Data Manager bulk card opened it. */
  startNote;

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
  deleteQueryJson;
  busy = false;
  errorMessage;
  noticeMessage;

  infoByObject = new Map();
  objectByPath = new Map();
  infoVersion = 0;
  previewSequence = 0;
  previewTimer;
  /** The message the last failed preview showed, so a good preview clears only that one. */
  previewError;

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
  enclosingTabId;

  /** In a console the tab is named for the object being searched. */
  @wire(EnclosingTabId)
  wiredTabId(tabId) {
    this.enclosingTabId = tabId;
    this.nameTab();
  }

  renderedCallback() {
    this.nameTab();
  }

  nameTab() {
    const object = this.objectOptions.find((option) => option.value === this.objectApiName);
    const label = object ? TAB_LABEL.replace('{0}', TITLE).replace('{1}', object.label) : TITLE;
    labelTab(this, label, 'utility:search');
  }

  /** Another page (Data Hygiene, C-28) can link to Find with a saved query to open and run. */
  @wire(CurrentPageReference)
  handlePageReference(pageReference) {
    const state = (pageReference && pageReference.state) || {};
    const toolKey = Object.keys(state).find((name) => name.endsWith(TOOL_STATE));
    this.startNote = toolKey ? START_NOTES[state[toolKey]] : undefined;
    const key = Object.keys(state).find((name) => name.endsWith(SAVED_QUERY_STATE));
    if (key && state[key]) {
      this.requestedSavedQueryId = state[key];
      this.openRequested();
    }
    const objectKey = Object.keys(state).find((name) => name.endsWith(OBJECT_STATE));
    if (objectKey && state[objectKey]) {
      this.requestedObject = state[objectKey];
      this.openRequestedObject();
    }
  }

  /** Chooses the object a link asked for, once the object list is loaded and it is in it. */
  async openRequestedObject() {
    const requested = this.requestedObject;
    if (!requested || !this.objectOptions.some((option) => option.value === requested)) {
      return;
    }
    this.requestedObject = undefined;
    if (requested !== this.objectApiName) {
      await this.handleObjectChange({ detail: { value: requested } });
    }
  }

  @wire(listObjects)
  wiredObjects({ data, error }) {
    if (data) {
      this.objectOptions = data.map((option) => ({ label: option.label, value: option.value }));
      this.openRequestedObject();
    } else if (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  connectedCallback() {
    this.loadPage();
  }

  disconnectedCallback() {
    clearTimeout(this.previewTimer);
  }

  async loadPage() {
    try {
      this.page = await getPage();
    } catch (error) {
      this.errorMessage = messageFrom(error);
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
      if (dataType === 'datetime') {
        shown.typeAttributes = DATETIME_ATTRIBUTES;
      }
      if (this.editableFields.has(column.key)) {
        shown.editable = true;
      }
      return shown;
    });
  }

  /** The rows on screen: the first `shownCount` of those the run read. */
  get visibleRows() {
    return this.tableRows.slice(0, this.shownCount);
  }

  get hasMore() {
    return !!this.rows && this.rows.length > this.shownCount;
  }

  get showingLine() {
    return format(
      SHOWING_OF,
      String(Math.min(this.shownCount, this.rows.length)),
      String(this.rows.length)
    );
  }

  get hasStartNote() {
    return Boolean(this.startNote);
  }

  get canChangeRecords() {
    return this.canBulkUpdate || this.canBulkDelete;
  }

  handleShowMore() {
    this.shownCount += PAGE_SIZE;
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

  get canBulkDelete() {
    return Boolean(this.page && this.page.canBulkDelete);
  }

  get showBulkDelete() {
    return Boolean(this.deleteQueryJson);
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

  /**
   * Asks for the SOQL after a pause in typing, so "Springfield" costs one server compile and
   * not eleven. The bulk panels close at once: the query they were opened with has changed.
   */
  schedulePreview() {
    this.bulkQueryJson = undefined;
    this.deleteQueryJson = undefined;
    clearTimeout(this.previewTimer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.previewTimer = setTimeout(() => this.refreshPreview(), PREVIEW_DEBOUNCE_MS);
  }

  async refreshPreview() {
    clearTimeout(this.previewTimer);
    // A bulk panel acts on the query it was opened with; an edited query closes it.
    this.bulkQueryJson = undefined;
    this.deleteQueryJson = undefined;
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
        // Only the preview's own error goes; a run or save error stays while the person types.
        if (this.previewError && this.errorMessage === this.previewError) {
          this.errorMessage = undefined;
        }
        this.previewError = undefined;
      }
    } catch (error) {
      if (sequence === this.previewSequence) {
        this.soql = '';
        this.previewError = messageFrom(error);
        this.errorMessage = this.previewError;
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
    this.schedulePreview();
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
    this.schedulePreview();
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
    this.schedulePreview();
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
      this.shownCount = PAGE_SIZE;
      this.draftValues = [];
      this.tableErrors = undefined;
    });
  }

  /** The Export, Change Records and query menus: each item's value names its action. */
  handleMenuSelect(event) {
    const actions = {
      export: () => this.handleExport(),
      'export-excel': () => this.handleExportExcel(),
      'export-files': () => this.handleExportFiles(),
      'bulk-update': () => this.handleBulkUpdate(),
      'bulk-delete': () => this.handleBulkDelete(),
      'save-as': () => this.handleSaveAs(),
      delete: () => this.handleDelete()
    };
    const action = actions[event.detail.value];
    return action ? action() : undefined;
  }

  handleExport() {
    return this.exportAs('csv');
  }

  handleExportExcel() {
    return this.exportAs('xlsx');
  }

  /**
   * Hands the query and each field column's label to the export to Files (R-SQ12), which runs
   * on the server; related record columns are not part of it.
   */
  handleExportFiles() {
    this.noticeMessage = undefined;
    if (!this.checkReady()) {
      return;
    }
    const labelsByPath = {};
    for (const path of this.columns) {
      labelsByPath[path] = this.columnLabel(path);
    }
    this.template.querySelector('c-find-export-files').start(this.queryDocument(), labelsByPath);
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
      const columns = this.outputColumns();
      // A CSV writes a date-time as the clock reads in the person's Salesforce time zone; the
      // workbook converts it itself, as a date it can sort.
      const readers = columns.map((column) => {
        if (kind !== 'xlsx' && column.field?.dataType === 'datetime') {
          return (row) => zonedDateTime(column.valueOf(row), TIME_ZONE);
        }
        return column.valueOf;
      });
      // Each record becomes its row of cells as its page arrives, so only one copy is held.
      const rows = [];
      let afterId = null;
      let done = false;
      let leftOver = false;
      while (!done && rows.length < limit) {
        // Each page starts after the last Id of the one before, so pages are read in turn.
        // eslint-disable-next-line no-await-in-loop
        const result = await exportPage({ queryJson, afterId });
        for (const row of result.rows) {
          if (rows.length < limit) {
            rows.push(readers.map((read) => read(row)));
          } else {
            leftOver = true;
          }
        }
        afterId = result.lastId;
        done = result.done;
        this.noticeMessage = format(EXPORTING, String(rows.length));
      }
      const stopped = leftOver || (rows.length >= limit && !done);
      if (kind === 'xlsx') {
        const bytes = await writeXlsx(
          columns.map((column) => ({
            label: column.label,
            type: XLSX_TYPES[column.field?.dataType] || CELL_TYPES.TEXT
          })),
          rows,
          { sheetName: this.objectApiName, timeZone: TIME_ZONE }
        );
        this.download(
          new Blob([bytes], {
            type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
          }),
          fileName(this.objectApiName, new Date(), 'xlsx')
        );
      } else {
        this.download(
          new Blob(
            [
              // Each row is an array, so a column's path is its position.
              toCsv(
                columns.map((column, index) => ({ label: column.label, path: String(index) })),
                rows
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
      // Names are not unique: the Id the save wrote decides which query stays open.
      if (this.page.savedId) {
        this.openQueryId = this.page.savedId;
      } else if (saved) {
        this.openQueryId = saved.recordId;
      }
      this.noticeMessage = format(SAVED_NOTICE, this.queryName.trim());
    });
  }

  async handleDelete() {
    const name = this.openQuery ? this.openQuery.name : '';
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: DELETE_CONFIRM_HEADING,
      message: format(DELETE_CONFIRM_BODY, name),
      details: this.openQuery && this.openQuery.shared ? [DELETE_CONFIRM_SHARED] : [],
      confirmLabel: DELETE_LABEL,
      cancelLabel: DELETE_CONFIRM_CANCEL,
      confirmVariant: 'destructive'
    });
    if (!confirmed) {
      return;
    }
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
    this.deleteQueryJson = undefined;
    this.bulkQueryJson = this.queryDocument();
  }

  handleBulkClose() {
    this.bulkQueryJson = undefined;
  }

  /** Opens bulk delete over the query as it is now (C-37); one bulk panel is open at a time. */
  handleBulkDelete() {
    this.noticeMessage = undefined;
    this.errorMessage = undefined;
    if (!this.checkReady()) {
      return;
    }
    this.bulkQueryJson = undefined;
    this.deleteQueryJson = this.queryDocument();
  }

  handleDeleteClose() {
    this.deleteQueryJson = undefined;
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
    // A shared query can name a column the person cannot see: it is left out, and they are told,
    // rather than kept where they can neither see nor remove it and every run refuses it.
    const fields = document.fields || [];
    const hidden = fields.filter((path) => !this.fieldOf(path));
    this.columns = fields.filter((path) => this.fieldOf(path));
    if (hidden.length > 0) {
      this.noticeMessage = format(HIDDEN_COLUMNS, hidden.join(', '));
    }
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
    this.deleteQueryJson = undefined;
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
      this.errorMessage = messageFrom(error);
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
}
