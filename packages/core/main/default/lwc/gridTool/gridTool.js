import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { labelTab } from 'c/workspaceTabs';
import BarnConfirmModal from 'c/barnConfirmModal';
import getPage from '@salesforce/apex/FindController.getPage';
import runQuery from '@salesforce/apex/FindController.runQuery';
import saveEdits from '@salesforce/apex/FindController.saveEdits';
import saveQuery from '@salesforce/apex/FindController.saveQuery';
import deleteQuery from '@salesforce/apex/FindController.deleteQuery';
import listChildRelationships from '@salesforce/apex/FindController.listChildRelationships';
import getTargets from '@salesforce/apex/BulkUpdateController.getTargets';
import getObjectInfo from '@salesforce/apex/QueryFieldCatalog.getObjectInfo';
import { iconFor } from 'c/barnIcons';
import { tabPageReference } from 'c/barnTabs';
import { format, messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import {
  PARENT_COLUMN,
  columnsFor,
  flatRow,
  gridDocument,
  isSavedGrid,
  mergeDrafts,
  parentLabel,
  parseDocument,
  refusedDrafts,
  relatedRows,
  sourceOptions
} from 'c/gridModel';

/** The page state key Find uses to open a saved query, matched and written by suffix. */
const SAVED_QUERY_STATE = '__savedQueryId';
const FIND_TAB = 'Find';
const GUIDE_URL =
  'https://github.com/Nonprofit-Collaborative/BarnCRM/blob/main/docs/user-guide/grid.md';

/**
 * The Grid tool (C-41, C-41b; admin guide grid.md): a saved Find query's records in an editable
 * table, with up to two kinds of related record in tables of their own on the same screen,
 * saved as a named grid. Everything goes through Find's own server methods: the query runs in
 * user mode, edits save as Find's inline edits do (one undoable data job per save, bulk update
 * permission needed), and a saved grid is a saved query whose document carries a `grid` key.
 */
export default class GridTool extends NavigationMixin(LightningElement) {
  /** Set by c/findPage: the page state key that opened the Grid, such as `c__view`. */
  @api stateKey;

  helpReady = isHelpLoaded('Core');
  iconName = iconFor('Find');

  page;
  sourceId;
  document;
  children = [];
  childOptions = [];
  rows;
  selectedIds = [];
  fieldsByObject = {};
  editableByObject = {};
  drafts = {};
  tableErrors = {};
  gridName = '';
  shared = false;
  busy = false;
  errorMessage;
  statusMessage;

  get labels() {
    return {
      title: helpText('Core', 'Core_Grid_Title'),
      intro: helpText('Core', 'Core_Grid_Intro'),
      source: helpText('Core', 'Core_Grid_Source'),
      sourcePlaceholder: helpText('Core', 'Core_Grid_SourcePlaceholder'),
      run: helpText('Core', 'Core_Grid_Run'),
      records: helpText('Core', 'Core_Grid_Records'),
      selectHint: helpText('Core', 'Core_Grid_SelectHint'),
      empty: helpText('Core', 'Core_Grid_Empty'),
      noRows: helpText('Core', 'Core_Grid_NoRows'),
      readOnly: helpText('Core', 'Core_Grid_ReadOnly'),
      limits: helpText('Core', 'Core_Grid_Limits'),
      name: helpText('Core', 'Core_Grid_Name'),
      share: helpText('Core', 'Core_Grid_Share'),
      save: helpText('Core', 'Core_Grid_Save'),
      saveAs: helpText('Core', 'Core_Grid_SaveAs'),
      remove: helpText('Core', 'Core_Grid_Delete'),
      openInFind: helpText('Core', 'Core_Grid_OpenInFind'),
      noRelated: helpText('Core', 'Core_Grid_NoRelated')
    };
  }

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
        labelTab(this, this.labels.title, 'utility:table');
      });
    } else {
      labelTab(this, this.labels.title, 'utility:table');
    }
    this.loadPage();
  }

  async loadPage(keepId) {
    try {
      this.page = await getPage();
      if (keepId) {
        this.sourceId = keepId;
      }
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  /* ---------- what the template reads ---------- */

  get sourceChoices() {
    return sourceOptions(
      this.page && this.page.savedQueries,
      helpText('Core', 'Core_Grid_GridOption')
    );
  }

  get hasSources() {
    return this.sourceChoices.length > 0;
  }

  get openQuery() {
    const queries = (this.page && this.page.savedQueries) || [];
    return queries.find((query) => query.recordId === this.sourceId);
  }

  get isOwnGrid() {
    const query = this.openQuery;
    return Boolean(query && query.mine && isSavedGrid(query.queryJson));
  }

  get objectApiName() {
    return this.document ? this.document.object : undefined;
  }

  get related() {
    return (this.document && this.document.related) || [];
  }

  get guideUrl() {
    return GUIDE_URL;
  }

  get hasDocument() {
    return Boolean(this.document);
  }

  get canEdit() {
    return Boolean(this.page && this.page.canBulkUpdate);
  }

  get runDisabled() {
    return this.busy || !this.document;
  }

  get saveDisabled() {
    return this.busy || !this.document || !this.gridName.trim();
  }

  get deleteDisabled() {
    return this.busy || !this.isOwnGrid;
  }

  get saveLabel() {
    return this.isOwnGrid ? this.labels.save : this.labels.saveAs;
  }

  get hasRows() {
    return Array.isArray(this.rows) && this.rows.length > 0;
  }

  get showNoRows() {
    return Array.isArray(this.rows) && this.rows.length === 0;
  }

  get mainColumns() {
    return columnsFor(
      this.document.fields,
      this.fieldsByObject[this.objectApiName],
      this.editableByObject[this.objectApiName]
    );
  }

  get mainRows() {
    return (this.rows || []).map((row) => flatRow(row, this.document.fields));
  }

  get mainDrafts() {
    return this.drafts.main || [];
  }

  get mainErrors() {
    return this.tableErrors.main;
  }

  /** One table per related record column, each with its own object, columns, rows and drafts. */
  get relatedTables() {
    return this.children.map((child) => {
      const option =
        this.childOptions.find((each) => each.relationshipName === child.relationship) || {};
      const objectName = option.objectName;
      const key = `child:${child.relationship}`;
      const columns = [
        { label: helpText('Core', 'Core_Grid_Parent'), fieldName: PARENT_COLUMN, type: 'text' },
        ...columnsFor(
          child.fields,
          this.fieldsByObject[objectName],
          this.editableByObject[objectName]
        )
      ];
      const rows = relatedRows(this.rows, child, this.selectedIds, (row) =>
        parentLabel(row, this.document.fields)
      );
      return {
        key,
        objectName,
        heading: option.label || child.relationship,
        columns,
        rows,
        hasRows: rows.length > 0,
        drafts: this.drafts[key] || [],
        errors: this.tableErrors[key]
      };
    });
  }

  get hasRelated() {
    return this.children.length > 0;
  }

  /* ---------- choosing and running ---------- */

  async handleSourceChange(event) {
    this.sourceId = event.detail.value;
    const query = this.openQuery;
    this.document = query ? parseDocument(query.queryJson) : null;
    this.children = (this.document && this.document.children) || [];
    this.gridName = query && isSavedGrid(query.queryJson) ? query.name : '';
    this.shared = Boolean(query && query.shared);
    this.rows = undefined;
    this.selectedIds = [];
    this.drafts = {};
    this.tableErrors = {};
    this.errorMessage = undefined;
    this.statusMessage = undefined;
    if (this.document) {
      await this.describe(this.objectApiName);
      await this.loadChildOptions();
    }
  }

  handleRelatedChange(event) {
    this.children = event.detail.children || [];
    this.document = { ...this.document, related: event.detail.related || [] };
    this.rows = undefined;
    this.loadChildOptions();
  }

  async loadChildOptions() {
    try {
      this.childOptions =
        (await listChildRelationships({ objectApiName: this.objectApiName })) || [];
      const objects = this.children
        .map((child) =>
          this.childOptions.find((each) => each.relationshipName === child.relationship)
        )
        .filter(Boolean)
        .map((option) => option.objectName);
      await Promise.all(objects.map((objectName) => this.describe(objectName)));
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  /** The object's fields and, for someone who may bulk update, the fields they may change. */
  async describe(objectName) {
    if (!objectName || this.fieldsByObject[objectName]) {
      return;
    }
    const info = await getObjectInfo({ objectApiName: objectName }).catch(() => null);
    const targets = this.canEdit ? (await getTargets({ objectName }).catch(() => [])) || [] : [];
    this.fieldsByObject = { ...this.fieldsByObject, [objectName]: (info && info.fields) || [] };
    this.editableByObject = {
      ...this.editableByObject,
      [objectName]: new Set(targets.map((target) => target.apiName))
    };
  }

  queryJson() {
    return gridDocument(this.document, this.children);
  }

  async handleRun() {
    this.busy = true;
    this.errorMessage = undefined;
    try {
      const result = await runQuery({ queryJson: this.queryJson() });
      this.rows = result.rows || [];
      this.selectedIds = [];
      this.drafts = {};
      this.tableErrors = {};
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.busy = false;
    }
  }

  handleRowSelection(event) {
    this.selectedIds = (event.detail.selectedRows || []).map((row) => row.Id);
  }

  /* ---------- editing ---------- */

  handleCellChange(event) {
    const key = event.target.dataset.key;
    this.drafts = {
      ...this.drafts,
      [key]: mergeDrafts(this.drafts[key], event.detail.draftValues)
    };
  }

  handleCancel(event) {
    const key = event.target.dataset.key;
    this.drafts = { ...this.drafts, [key]: [] };
    this.tableErrors = { ...this.tableErrors, [key]: undefined };
  }

  async handleSave(event) {
    const key = event.target.dataset.key;
    const objectName = event.target.dataset.object;
    const drafts = mergeDrafts(this.drafts[key], event.detail.draftValues);
    this.busy = true;
    this.statusMessage = undefined;
    try {
      const summary = await saveEdits({
        objectApiName: objectName,
        editsJson: JSON.stringify(drafts)
      });
      const refused = refusedDrafts(drafts, summary.errors, (count) =>
        format(helpText('Core', 'Core_Grid_EditFailed'), String(count))
      );
      this.statusMessage = format(helpText('Core', 'Core_Grid_EditSaved'), String(summary.saved));
      const result = await runQuery({ queryJson: this.queryJson() });
      this.rows = result.rows || [];
      this.drafts = { ...this.drafts, [key]: refused.kept };
      this.tableErrors = { ...this.tableErrors, [key]: refused.errors };
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.busy = false;
    }
  }

  /* ---------- saved grids ---------- */

  handleNameChange(event) {
    this.gridName = event.detail.value || '';
  }

  handleShareChange(event) {
    this.shared = event.detail.checked;
  }

  async handleSaveGrid() {
    this.busy = true;
    this.errorMessage = undefined;
    try {
      const page = await saveQuery({
        recordId: this.isOwnGrid ? this.sourceId : null,
        name: this.gridName.trim(),
        queryJson: this.queryJson(),
        shared: this.shared
      });
      this.page = page;
      this.sourceId = page.savedId;
      this.statusMessage = helpText('Core', 'Core_Grid_Saved');
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.busy = false;
    }
  }

  async handleDeleteGrid() {
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: this.labels.remove,
      message: format(helpText('Core', 'Core_Grid_DeleteConfirm'), this.gridName),
      confirmLabel: this.labels.remove,
      cancelLabel: helpText('Core', 'Core_Grid_Cancel'),
      confirmVariant: 'destructive'
    });
    if (!confirmed) {
      return;
    }
    this.busy = true;
    try {
      this.page = await deleteQuery({ recordId: this.sourceId });
      this.sourceId = undefined;
      this.document = null;
      this.children = [];
      this.rows = undefined;
      this.gridName = '';
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.busy = false;
    }
  }

  /** Opens the saved query in Find, to change its fields or conditions. */
  async handleOpenInFind() {
    const stateKey = this.stateKeyPrefix() + SAVED_QUERY_STATE;
    this[NavigationMixin.Navigate](await tabPageReference(FIND_TAB, { [stateKey]: this.sourceId }));
  }

  /** `c`, or the namespace, read from the page's own view key (never a literal prefix). */
  stateKeyPrefix() {
    return this.stateKey ? this.stateKey.slice(0, this.stateKey.indexOf('__')) : 'c';
  }
}
