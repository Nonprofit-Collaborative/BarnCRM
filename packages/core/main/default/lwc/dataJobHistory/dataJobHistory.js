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
import getBackupRuns from '@salesforce/apex/BackupSetController.getRuns';
import getFilesJobs from '@salesforce/apex/FilesImportController.getJobs';
import undoFiles from '@salesforce/apex/FilesImportController.undo';
import { startPolling } from 'c/jobPoller';

import UNEXPECTED_ERROR from '@salesforce/label/c.Core_UnexpectedError';
import HEADING from '@salesforce/label/c.Core_DataJobs_Heading';
import EMPTY from '@salesforce/label/c.Core_DataJobs_Empty';
import SHOW from '@salesforce/label/c.Core_DataJobs_Show';
import SHOW_ALL from '@salesforce/label/c.Core_DataJobs_ShowAll';
import SHOW_IMPORTS from '@salesforce/label/c.Core_DataJobs_ShowImports';
import SHOW_UPDATES from '@salesforce/label/c.Core_DataJobs_ShowUpdates';
import SHOW_DELETES from '@salesforce/label/c.Core_DataJobs_ShowDeletes';
import KIND_IMPORT from '@salesforce/label/c.Core_DataJobs_KindImport';
import KIND_UPDATE from '@salesforce/label/c.Core_JobNotice_BulkUpdate';
import KIND_DELETE from '@salesforce/label/c.Core_JobNotice_BulkDelete';
import STARTED from '@salesforce/label/c.Core_DataJobs_Started';
import ROW_ACTIONS from '@salesforce/label/c.Core_DataJobs_RowActions';
import IMPORT_HEADING from '@salesforce/label/c.Core_Import_HistoryHeading';
import IMPORT_CONFIRM_HEADING from '@salesforce/label/c.Core_Import_UndoConfirmHeading';
import IMPORT_CONFIRM_PEOPLE from '@salesforce/label/c.Core_Import_UndoConfirmPeople';
import IMPORT_CONFIRM_HOUSEHOLDS from '@salesforce/label/c.Core_Import_UndoConfirmHouseholds';
import IMPORT_CONFIRM_ORGANIZATIONS from '@salesforce/label/c.Core_Import_UndoConfirmOrganizations';
import IMPORT_CONFIRM_UPDATES from '@salesforce/label/c.Core_Import_UndoConfirmUpdates';
import IMPORT_CONFIRM_BUTTON from '@salesforce/label/c.Core_Import_UndoConfirmButton';
import UPDATE_UNDO_BUTTON from '@salesforce/label/c.Core_BulkUpdate_UndoButton';
import DELETE_UNDO_BUTTON from '@salesforce/label/c.Core_BulkDelete_UndoButton';
import REFRESH from '@salesforce/label/c.Core_OrgOptimizer_Refresh';
import UNDO from '@salesforce/label/c.Core_AutoMerge_Undo';
import UNDO_UNTIL from '@salesforce/label/c.Core_BulkUpdate_UndoUntil';
import TYPE_TO_CONFIRM from '@salesforce/label/c.Core_BulkUpdate_Confirm';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';
import EVERYONE from '@salesforce/label/c.Core_BulkUpdate_EveryonesJobs';
import OPEN_FIND from '@salesforce/label/c.Core_BulkUpdate_OpenFind';
import { NavigationMixin } from 'lightning/navigation';
import findToolStateKey from '@salesforce/apex/DataManagerController.findToolStateKey';
import { format } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const FIND_TAB = 'Find';

const IMPORT = 'Import';
const UPDATE = 'Update';
const DELETE = 'Delete';
const BACKUP = 'Backup';
const FILES = 'Files';
const ALL_KINDS = [IMPORT, UPDATE, DELETE, BACKUP, FILES];
const IMPORTS_SHOWN = 10;

function errorText(error) {
  if (error && error.body && error.body.message) {
    return error.body.message;
  }
  return (error && error.message) || UNEXPECTED_ERROR;
}

// ImportBatchService.STATUS_UNDOING
const IMPORT_UNDOING = 'Undoing';

/**
 * The status badge tone for a job status (the kit's vocabulary): success when done, error when
 * it failed, running while it runs, neutral otherwise.
 */
function statusTone(status) {
  const text = String(status || '').toLowerCase();
  if (text.includes('fail') || text.includes('error')) {
    return 'error';
  }
  if (text.includes('ing') || text.startsWith('queued') || text.startsWith('pending')) {
    return 'running';
  }
  if (text.startsWith('complete') || text.startsWith('done') || text === 'undone') {
    return 'success';
  }
  return 'neutral';
}

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
      batch.rowCount === 1
        ? helpText('Core', 'Core_DataJobs_ImportSummaryOne')
        : helpText('Core', 'Core_DataJobs_ImportSummary'),
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
      ? format(
          helpText('Core', 'Core_BulkUpdate_Summary'),
          job.matched,
          job.updated,
          job.unchanged,
          job.failed
        )
      : format(helpText('Core', 'Core_BulkDelete_Summary'), job.matched, job.deleted, job.failed),
    startedAt: job.startedAt,
    undoDeadline: job.undoDeadline,
    canUndo: Boolean(job.canUndo && !job.running),
    running: Boolean(job.running),
    undoCount: isUpdate ? job.updatesToUndo : job.recordsToUndo
  };
}

/** One Backup Set run (C-66): nothing to undo; its file is opened from Backup Sets. */
function fromBackupRun(run) {
  return {
    key: run.id,
    id: run.id,
    kind: BACKUP,
    kindLabel: helpText('Core', 'Core_DataJobs_KindBackup'),
    name: run.name,
    detail: run.setName,
    status: run.status,
    summary: format(helpText('Core', 'Core_DataJobs_BackupSummary'), run.rows || 0),
    startedAt: run.startedAt,
    canUndo: false,
    running: Boolean(run.running)
  };
}

/** One files import (C-70): undone by typing the number of files it saved (R-FI4). */
function fromFilesJob(job) {
  return {
    key: job.id,
    id: job.id,
    kind: FILES,
    kindLabel: helpText('Core', 'Core_DataJobs_KindFiles'),
    name: job.name,
    detail: job.fileName,
    status: job.status,
    summary: format(helpText('Core', 'Core_DataJobs_FilesSummary'), job.saved, job.refused),
    startedAt: job.startedAt,
    undoDeadline: job.undoDeadline,
    canUndo: Boolean(job.canUndo),
    running: false,
    undoCount: job.saved
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
  helpReady = isHelpLoaded('Core');

  /** Which kinds this placement lists, comma separated (Import, Update, Delete); blank is all. */
  @api kinds;

  labels = {
    show: SHOW,
    empty: EMPTY,
    get emptyHint() {
      return helpText('Core', 'Core_DataJobs_EmptyHint');
    },
    refresh: REFRESH,
    undo: UNDO,
    undoUntil: UNDO_UNTIL,
    started: STARTED,
    rowActions: ROW_ACTIONS,
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
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
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
    const [imports, updates, deletes, backups, files] = await Promise.all([
      wanted.includes(IMPORT) && canManageSettings
        ? getRecentBatches({ howMany: IMPORTS_SHOWN })
        : null,
      wanted.includes(UPDATE) && canBulkUpdate ? getUpdatePage({ everyone: this.everyone }) : null,
      wanted.includes(DELETE) && canBulkDelete ? getDeletePage({ everyone: this.everyone }) : null,
      // The server says null to someone who may not use Backup Sets.
      wanted.includes(BACKUP) && canManageSettings ? getBackupRuns() : null,
      wanted.includes(FILES) && canManageSettings ? getFilesJobs() : null
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
    if (Array.isArray(backups)) {
      allowed.push(BACKUP);
      jobs = jobs.concat(backups.map(fromBackupRun));
    }
    if (Array.isArray(files)) {
      allowed.push(FILES);
      jobs = jobs.concat(files.map(fromFilesJob));
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
    return helpText('Core', 'Core_BulkUpdate_TabIntro');
  }

  get showFilter() {
    return this.allowedKinds.length > 1;
  }

  get filterOptions() {
    const names = {
      [IMPORT]: SHOW_IMPORTS,
      [UPDATE]: SHOW_UPDATES,
      [DELETE]: SHOW_DELETES,
      [BACKUP]: helpText('Core', 'Core_DataJobs_ShowBackups'),
      [FILES]: helpText('Core', 'Core_DataJobs_ShowFiles')
    };
    return [{ label: SHOW_ALL, value: 'all' }].concat(
      this.allowedKinds.map((kind) => ({ label: names[kind], value: kind }))
    );
  }

  get rows() {
    return this.jobs
      .filter((job) => this.filter === 'all' || job.kind === this.filter)
      .map((job) => ({
        ...job,
        title: `${job.name}: ${[job.kindLabel, job.detail].filter(Boolean).join(', ')}`,
        tone: statusTone(job.status),
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
      // An installed module's own records, such as gifts, each under the org's own label; one
      // this import made none of is left out.
      ...(view.others || [])
        .filter((other) => other.count > 0)
        .map((other) => ({
          key: `other-${other.objectName}`,
          label: other.label,
          value: other.count
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
    const templates = {
      [UPDATE]: helpText('Core', 'Core_BulkUpdate_UndoConfirm'),
      [DELETE]: helpText('Core', 'Core_BulkDelete_UndoConfirm'),
      [FILES]: helpText('Core', 'Core_FilesImport_UndoConfirm')
    };
    return format(templates[this.undoTarget.kind], this.undoTarget.undoCount);
  }

  get bulkUndoButton() {
    const kind = this.undoTarget && this.undoTarget.kind;
    if (kind === FILES) {
      return helpText('Core', 'Core_FilesImport_UndoButton');
    }
    return kind === DELETE ? DELETE_UNDO_BUTTON : UPDATE_UNDO_BUTTON;
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
      this.finishUndo(helpText('Core', 'Core_Import_UndoStarted'));
      await this.load();
    });
  }

  async handleBulkUndoConfirm() {
    await this.work(async () => {
      const target = this.undoTarget;
      if (target.kind === FILES) {
        // Synchronous: the files are deleted when it returns (R-FI4).
        const job = await undoFiles({ jobId: target.id, confirmedFiles: target.undoCount });
        const row = fromFilesJob(job);
        this.jobs = this.jobs.map((existing) => (existing.id === row.id ? row : existing));
        this.finishUndo(helpText('Core', 'Core_FilesImport_Undone'));
        return;
      }
      const undone =
        target.kind === UPDATE
          ? await undoUpdate({ jobId: target.id, confirmedUpdates: target.undoCount })
          : await undoDelete({ jobId: target.id, confirmedRecords: target.undoCount });
      if (undone) {
        const row = fromBulkJob(undone, target.kind);
        this.jobs = this.jobs.map((job) => (job.id === row.id ? row : job));
      }
      this.finishUndo(helpText('Core', 'Core_BulkUpdate_UndoStarted'));
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
