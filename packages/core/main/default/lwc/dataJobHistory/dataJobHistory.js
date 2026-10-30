import { LightningElement, api, wire } from 'lwc';
import canManageSettings from '@salesforce/customPermission/Manage_BarnCRM_Settings';
import canBulkUpdate from '@salesforce/customPermission/Bulk_Update_Records';
import canBulkDelete from '@salesforce/customPermission/Bulk_Delete_Records';
import getRecentBatches from '@salesforce/apex/ImportController.getRecentBatches';
import previewImportUndo from '@salesforce/apex/ImportController.previewUndo';
import startImportUndo from '@salesforce/apex/ImportController.startUndo';
import getUpdatePage from '@salesforce/apex/BulkUpdateController.getPage';
import undoUpdate from '@salesforce/apex/BulkUpdateController.undo';
import getDeletePage from '@salesforce/apex/BulkDeleteController.getPage';
import undoDelete from '@salesforce/apex/BulkDeleteController.undo';
import { startPolling } from 'c/jobPoller';

import UNEXPECTED_ERROR from '@salesforce/label/c.Core_UnexpectedError';
import HEADING from '@salesforce/label/c.Core_DataJobs_Heading';
import EMPTY from '@salesforce/label/c.Core_DataJobs_Empty';
import EMPTY_HINT from '@salesforce/label/c.Core_DataJobs_EmptyHint';
import SHOW from '@salesforce/label/c.Core_DataJobs_Show';
import SHOW_ALL from '@salesforce/label/c.Core_DataJobs_ShowAll';
import SHOW_IMPORTS from '@salesforce/label/c.Core_DataJobs_ShowImports';
import SHOW_UPDATES from '@salesforce/label/c.Core_DataJobs_ShowUpdates';
import SHOW_DELETES from '@salesforce/label/c.Core_DataJobs_ShowDeletes';
import KIND_IMPORT from '@salesforce/label/c.Core_DataJobs_KindImport';
import KIND_UPDATE from '@salesforce/label/c.Core_DataJobs_KindUpdate';
import KIND_DELETE from '@salesforce/label/c.Core_DataJobs_KindDelete';
import IMPORT_SUMMARY from '@salesforce/label/c.Core_DataJobs_ImportSummary';
import IMPORT_SUMMARY_ONE from '@salesforce/label/c.Core_DataJobs_ImportSummaryOne';
import STARTED from '@salesforce/label/c.Core_DataJobs_Started';
import IMPORT_HEADING from '@salesforce/label/c.Core_Import_HistoryHeading';
import IMPORT_CONFIRM_HEADING from '@salesforce/label/c.Core_Import_UndoConfirmHeading';
import IMPORT_CONFIRM_PEOPLE from '@salesforce/label/c.Core_Import_UndoConfirmPeople';
import IMPORT_CONFIRM_HOUSEHOLDS from '@salesforce/label/c.Core_Import_UndoConfirmHouseholds';
import IMPORT_CONFIRM_ORGANIZATIONS from '@salesforce/label/c.Core_Import_UndoConfirmOrganizations';
import IMPORT_CONFIRM_UPDATES from '@salesforce/label/c.Core_Import_UndoConfirmUpdates';
import IMPORT_CONFIRM_BUTTON from '@salesforce/label/c.Core_Import_UndoConfirmButton';
import IMPORT_UNDO_STARTED from '@salesforce/label/c.Core_Import_UndoStarted';
import UPDATE_INTRO from '@salesforce/label/c.Core_BulkUpdate_TabIntro';
import UPDATE_SUMMARY from '@salesforce/label/c.Core_BulkUpdate_Summary';
import UPDATE_UNDO_CONFIRM from '@salesforce/label/c.Core_BulkUpdate_UndoConfirm';
import UPDATE_UNDO_BUTTON from '@salesforce/label/c.Core_BulkUpdate_UndoButton';
import DELETE_SUMMARY from '@salesforce/label/c.Core_BulkDelete_Summary';
import DELETE_UNDO_CONFIRM from '@salesforce/label/c.Core_BulkDelete_UndoConfirm';
import DELETE_UNDO_BUTTON from '@salesforce/label/c.Core_BulkDelete_UndoButton';
import BULK_UNDO_STARTED from '@salesforce/label/c.Core_BulkUpdate_UndoStarted';
import REFRESH from '@salesforce/label/c.Core_BulkUpdate_Refresh';
import UNDO from '@salesforce/label/c.Core_BulkUpdate_Undo';
import UNDO_UNTIL from '@salesforce/label/c.Core_BulkUpdate_UndoUntil';
import TYPE_TO_CONFIRM from '@salesforce/label/c.Core_BulkUpdate_Confirm';
import CANCEL from '@salesforce/label/c.Core_BulkUpdate_Cancel';
import LOADING from '@salesforce/label/c.Core_BulkUpdate_Loading';
import EVERYONE from '@salesforce/label/c.Core_BulkUpdate_EveryonesJobs';
import OPEN_FIND from '@salesforce/label/c.Core_BulkUpdate_OpenFind';
import { NavigationMixin } from 'lightning/navigation';
import findToolStateKey from '@salesforce/apex/DataManagerController.findToolStateKey';

const FIND_TAB = 'Find';

const IMPORT = 'Import';
const UPDATE = 'Update';
const DELETE = 'Delete';
const ALL_KINDS = [IMPORT, UPDATE, DELETE];
const IMPORTS_SHOWN = 10;

function format(template, ...values) {
  return values.reduce((text, value, index) => text.split(`{${index}}`).join(value), template);
}

function errorText(error) {
  if (error && error.body && error.body.message) {
    return error.body.message;
  }
  return (error && error.message) || UNEXPECTED_ERROR;
}

// ImportBatchService.STATUS_UNDOING
const IMPORT_UNDOING = 'Undoing';

/** One import, in the shape every row of the list shares. */
function fromImport(batch) {
  return {
    key: batch.id,
    id: batch.id,
    kind: IMPORT,
    kindLabel: KIND_IMPORT,
    name: batch.name,
    detail: batch.fileName,
    status: batch.status,
    summary: format(
      batch.rowCount === 1 ? IMPORT_SUMMARY_ONE : IMPORT_SUMMARY,
      batch.rowCount || 0,
      batch.created || 0,
      batch.updated || 0,
      batch.matched || 0,
      batch.rejected || 0
    ),
    startedAt: batch.startedAt,
    undoDeadline: batch.undoDeadline,
    canUndo: Boolean(batch.canUndo),
    // An undo shows as Undoing until it ends; the list keeps reading until it does.
    running: batch.status === IMPORT_UNDOING
  };
}

/** One bulk update or bulk delete, in the shape every row of the list shares. */
function fromBulkJob(job, kind) {
  const isUpdate = kind === UPDATE;
  return {
    key: job.recordId,
    id: job.recordId,
    kind,
    kindLabel: isUpdate ? KIND_UPDATE : KIND_DELETE,
    name: job.name,
    detail: job.objectLabel,
    status: job.status,
    summary: isUpdate
      ? format(UPDATE_SUMMARY, job.matched, job.updated, job.unchanged, job.failed)
      : format(DELETE_SUMMARY, job.matched, job.deleted, job.failed),
    startedAt: job.startedAt,
    undoDeadline: job.undoDeadline,
    canUndo: Boolean(job.canUndo && !job.running),
    running: Boolean(job.running),
    undoCount: isUpdate ? job.updatesToUndo : job.recordsToUndo
  };
}

function newestFirst(left, right) {
  const leftTime = left.startedAt ? new Date(left.startedAt).getTime() : 0;
  const rightTime = right.startedAt ? new Date(right.startedAt).getTime() : 0;
  if (leftTime !== rightTime) {
    return rightTime - leftTime;
  }
  // Job numbers are one sequence across every kind of data job (ADR-0047).
  return String(right.name).localeCompare(String(left.name));
}

/**
 * Every data job in one list: imports, bulk updates and bulk deletes, newest first, with the
 * undo of each (ADR-0103 org-optimizer-and-data-manager-pages, admin guide data-manager.md).
 *
 * Each kind is read from its own controller, which keeps its own permission check, and only
 * for a holder of that tool's custom permission (whose permission set also grants the
 * controller): imports for Manage BarnCRM Settings, bulk updates for Bulk Update Records, bulk
 * deletes for Bulk Delete Records; a bulk kind is listed when its page says allowed. Undo uses each tool's own confirmation unchanged: the import undo shows what it
 * would remove and put back (canonical model R-IB8); a bulk undo is confirmed by typing the
 * number it acts on (R-BU5, R-BD5).
 */
export default class DataJobHistory extends NavigationMixin(LightningElement) {
  /** Which kinds this placement lists, comma separated (Import, Update, Delete); blank is all. */
  @api kinds;

  labels = {
    show: SHOW,
    empty: EMPTY,
    emptyHint: EMPTY_HINT,
    refresh: REFRESH,
    undo: UNDO,
    undoUntil: UNDO_UNTIL,
    started: STARTED,
    typeToConfirm: TYPE_TO_CONFIRM,
    cancel: CANCEL,
    loading: LOADING,
    importConfirmButton: IMPORT_CONFIRM_BUTTON,
    everyone: EVERYONE,
    openFind: OPEN_FIND
  };

  /** Find's tool state key, with the namespace's prefix (never a literal `c__`). */
  toolStateKey;

  @wire(findToolStateKey)
  wiredToolStateKey({ data }) {
    if (data) {
      this.toolStateKey = data;
    }
  }

  /** A bulk update starts in Find (D-135): opens it with the note that says where. */
  handleOpenFind() {
    const pageReference = { type: 'standard__navItemPage', attributes: { apiName: FIND_TAB } };
    if (this.toolStateKey) {
      pageReference.state = { [this.toolStateKey]: 'update' };
    }
    this[NavigationMixin.Navigate](pageReference);
  }

  jobs = [];
  allowedKinds = [];
  /** Whether the person may list everyone's bulk jobs, and whether they asked to. */
  canSeeEveryone = false;
  everyone = false;
  filter = 'all';
  loading = true;
  busy = false;
  errorMessage;
  noticeMessage;
  /** The job being undone, the import undo's preview, and what the person typed. */
  undoTarget;
  importPreview;
  undoText = '';
  stopTimer;

  connectedCallback() {
    this.load();
  }

  disconnectedCallback() {
    this.stopPolling();
  }

  get anyRunning() {
    return this.jobs.some((job) => job.running);
  }

  /**
   * While a job in the list is running (a bulk job, or an undo still Undoing), reads the list
   * again without the spinner, slowing down after a minute and retrying once on an error
   * (c/jobPoller), so a row does not stay Undoing until the person presses Refresh (FINDB-19).
   */
  pollWhileRunning() {
    if (this.stopTimer || !this.anyRunning) {
      return;
    }
    this.stopTimer = startPolling(
      async () => {
        await this.fetchJobs();
        if (!this.anyRunning) {
          this.stopPolling();
          return true;
        }
        return false;
      },
      (error) => {
        this.stopPolling();
        this.errorMessage = errorText(error);
      }
    );
  }

  stopPolling() {
    if (this.stopTimer) {
      this.stopTimer();
      this.stopTimer = undefined;
    }
  }

  get wantedKinds() {
    const named = String(this.kinds || '')
      .split(',')
      .map((kind) => kind.trim())
      .filter((kind) => ALL_KINDS.includes(kind));
    return named.length ? named : ALL_KINDS;
  }

  async load() {
    this.loading = true;
    this.errorMessage = undefined;
    try {
      await this.fetchJobs();
    } catch (error) {
      this.errorMessage = errorText(error);
    } finally {
      this.loading = false;
    }
    this.pollWhileRunning();
  }

  /** Reads every list this placement shows and replaces the rows; throws when a read fails. */
  async fetchJobs() {
    const wanted = this.wantedKinds;
    const [imports, updates, deletes] = await Promise.all([
      wanted.includes(IMPORT) && canManageSettings
        ? getRecentBatches({ howMany: IMPORTS_SHOWN })
        : null,
      wanted.includes(UPDATE) && canBulkUpdate ? getUpdatePage({ everyone: this.everyone }) : null,
      wanted.includes(DELETE) && canBulkDelete ? getDeletePage({ everyone: this.everyone }) : null
    ]);
    this.canSeeEveryone = Boolean(
      (updates && updates.allowed && updates.canSeeEveryone) ||
      (deletes && deletes.allowed && deletes.canSeeEveryone)
    );
    const allowed = [];
    let jobs = [];
    if (imports) {
      allowed.push(IMPORT);
      jobs = jobs.concat(imports.map(fromImport));
    }
    if (updates && updates.allowed) {
      allowed.push(UPDATE);
      jobs = jobs.concat((updates.jobs || []).map((job) => fromBulkJob(job, UPDATE)));
    }
    if (deletes && deletes.allowed) {
      allowed.push(DELETE);
      jobs = jobs.concat((deletes.jobs || []).map((job) => fromBulkJob(job, DELETE)));
    }
    this.allowedKinds = allowed;
    this.jobs = jobs.sort(newestFirst);
  }

  /** Nothing renders for a person who may see none of the kinds this placement lists. */
  get visible() {
    return this.loading || this.allowedKinds.length > 0 || Boolean(this.errorMessage);
  }

  get heading() {
    if (this.wantedKinds.length === 1 && this.wantedKinds[0] === IMPORT) {
      return IMPORT_HEADING;
    }
    return HEADING;
  }

  /** The bulk update tab's guidance, where bulk updates are listed. */
  get showIntro() {
    return this.allowedKinds.includes(UPDATE);
  }

  get introText() {
    return UPDATE_INTRO;
  }

  get showFilter() {
    return this.allowedKinds.length > 1;
  }

  get filterOptions() {
    const names = { [IMPORT]: SHOW_IMPORTS, [UPDATE]: SHOW_UPDATES, [DELETE]: SHOW_DELETES };
    return [{ label: SHOW_ALL, value: 'all' }].concat(
      this.allowedKinds.map((kind) => ({ label: names[kind], value: kind }))
    );
  }

  get rows() {
    return this.jobs
      .filter((job) => this.filter === 'all' || job.kind === this.filter)
      .map((job) => ({
        ...job,
        title: `${job.name}: ${[job.kindLabel, job.detail, job.status].filter(Boolean).join(', ')}`,
        showDeadline: job.canUndo && Boolean(job.undoDeadline)
      }));
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get hasError() {
    return Boolean(this.errorMessage);
  }

  get hasNotice() {
    return Boolean(this.noticeMessage);
  }

  get isImportUndo() {
    return Boolean(this.undoTarget && this.undoTarget.kind === IMPORT);
  }

  get isBulkUndo() {
    return Boolean(this.undoTarget && this.undoTarget.kind !== IMPORT);
  }

  get importConfirmTitle() {
    return this.undoTarget ? format(IMPORT_CONFIRM_HEADING, this.undoTarget.name) : '';
  }

  get importCounts() {
    const view = this.importPreview || {};
    return [
      { key: 'people', label: IMPORT_CONFIRM_PEOPLE, value: view.people || 0 },
      { key: 'households', label: IMPORT_CONFIRM_HOUSEHOLDS, value: view.households || 0 },
      { key: 'organizations', label: IMPORT_CONFIRM_ORGANIZATIONS, value: view.organizations || 0 },
      // An installed module's own records, such as gifts, each under the org's own label.
      ...(view.others || []).map((other) => ({
        key: `other-${other.objectName}`,
        label: other.label,
        value: other.count || 0
      })),
      { key: 'updates', label: IMPORT_CONFIRM_UPDATES, value: view.updates || 0 }
    ];
  }

  get importConfirmDisabled() {
    return this.busy || !(this.importPreview && this.importPreview.allowed);
  }

  get bulkUndoLine() {
    if (!this.isBulkUndo) {
      return '';
    }
    const template = this.undoTarget.kind === UPDATE ? UPDATE_UNDO_CONFIRM : DELETE_UNDO_CONFIRM;
    return format(template, this.undoTarget.undoCount);
  }

  get bulkUndoButton() {
    return this.undoTarget && this.undoTarget.kind === DELETE
      ? DELETE_UNDO_BUTTON
      : UPDATE_UNDO_BUTTON;
  }

  get bulkUndoDisabled() {
    return (
      this.busy ||
      !this.isBulkUndo ||
      String(this.undoText).trim() !== String(this.undoTarget.undoCount)
    );
  }

  handleFilter(event) {
    this.filter = event.detail.value;
  }

  /** Lists every person's bulk updates and deletes, for someone who manages settings. */
  handleEveryone(event) {
    this.everyone = event.target.checked;
    this.load();
  }

  async handleRefresh() {
    this.noticeMessage = undefined;
    await this.load();
  }

  async handleUndo(event) {
    const id = event.currentTarget.dataset.id;
    this.undoTarget = this.jobs.find((job) => job.id === id);
    this.importPreview = undefined;
    this.undoText = '';
    this.noticeMessage = undefined;
    if (this.isImportUndo) {
      await this.work(async () => {
        this.importPreview = await previewImportUndo({ batchId: id });
        if (this.importPreview && !this.importPreview.allowed) {
          this.errorMessage = this.importPreview.reason;
        }
      });
    }
  }

  handleUndoText(event) {
    this.undoText = event.detail.value;
  }

  handleUndoCancel() {
    this.undoTarget = undefined;
    this.importPreview = undefined;
    this.undoText = '';
    this.errorMessage = undefined;
  }

  async handleImportUndoConfirm() {
    await this.work(async () => {
      await startImportUndo({
        batchId: this.undoTarget.id,
        confirmedTotal: this.importPreview.total
      });
      this.finishUndo(IMPORT_UNDO_STARTED);
      await this.load();
    });
  }

  async handleBulkUndoConfirm() {
    await this.work(async () => {
      const target = this.undoTarget;
      const undone =
        target.kind === UPDATE
          ? await undoUpdate({ jobId: target.id, confirmedUpdates: target.undoCount })
          : await undoDelete({ jobId: target.id, confirmedRecords: target.undoCount });
      if (undone) {
        const row = fromBulkJob(undone, target.kind);
        this.jobs = this.jobs.map((job) => (job.id === row.id ? row : job));
      }
      this.finishUndo(BULK_UNDO_STARTED);
      this.pollWhileRunning();
    });
  }

  finishUndo(notice) {
    this.undoTarget = undefined;
    this.importPreview = undefined;
    this.undoText = '';
    this.noticeMessage = notice;
  }

  async work(action) {
    this.busy = true;
    this.errorMessage = undefined;
    try {
      await action();
    } catch (error) {
      this.errorMessage = errorText(error);
    } finally {
      this.busy = false;
    }
  }
}
