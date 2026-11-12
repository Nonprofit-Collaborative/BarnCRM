import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import LightningConfirm from 'lightning/confirm';
import { refreshApex } from '@salesforce/apex';
// Bare, and correctly so: a custom permission defined in the same package resolves without a
// namespace prefix.
import canManageSettings from '@salesforce/customPermission/Manage_BarnCRM_Settings';
import getPage from '@salesforce/apex/RollupController.getPage';
import restoreDefaults from '@salesforce/apex/RollupController.restoreDefaults';
import setActive from '@salesforce/apex/RollupController.setActive';
import setMode from '@salesforce/apex/RollupController.setMode';
import recalculate from '@salesforce/apex/RollupController.recalculate';
import recalculateAll from '@salesforce/apex/RollupController.recalculateAll';
import setSchedule from '@salesforce/apex/RollupController.setSchedule';
import estimateFullRun from '@salesforce/apex/RollupController.estimateFullRun';
import runTonight from '@salesforce/apex/RollupController.runTonight';
import deleteRollup from '@salesforce/apex/RollupController.deleteRollup';
import exportDefinitions from '@salesforce/apex/RollupDefinitionTransfer.exportDefinitions';
import importDefinitions from '@salesforce/apex/RollupDefinitionTransfer.importDefinitions';

import TITLE from '@salesforce/label/c.Core_Rollups_PageTitle';
import COLUMN_ROLLUP from '@salesforce/label/c.Core_Rollups_ColumnRollup';
import COLUMN_COUNTS from '@salesforce/label/c.Core_Rollups_ColumnCounts';
import COUNTS_SEPARATED_BY from '@salesforce/label/c.Core_Rollups_CountsSeparatedBy';
import COLUMN_MODE from '@salesforce/label/c.Core_Rollups_ColumnMode';
import COLUMN_ACTIVE from '@salesforce/label/c.Core_MatchLogic_Active';
import COLUMN_LAST_CALCULATED from '@salesforce/label/c.Core_Rollups_ColumnLastCalculated';
import RECALCULATE from '@salesforce/label/c.Core_Rollups_Recalculate';
import RECALCULATE_ALL from '@salesforce/label/c.Core_Rollups_RecalculateAll';
import SCHEDULE_NIGHTLY from '@salesforce/label/c.Core_Rollups_ScheduleNightly';
import STOP_SCHEDULE from '@salesforce/label/c.Core_Rollups_StopSchedule';
import RESTORE_DEFAULTS from '@salesforce/label/c.Core_Rollups_RestoreDefaults';
import NEVER_CALCULATED from '@salesforce/label/c.Core_Rollups_NeverCalculated';
import FRESHNESS_TITLE from '@salesforce/label/c.Core_Rollups_FreshnessTitle';
import FRESHNESS_STALE from '@salesforce/label/c.Core_Rollups_FreshnessStale';
import NEW_ROLLUP from '@salesforce/label/c.Core_RollupBuilder_New';
import EDIT from '@salesforce/label/c.Core_CmdtManager_EditAction';
import COPY from '@salesforce/label/c.Core_RecordInspector_Copy';
import OPEN_BUILDER from '@salesforce/label/c.Core_HealthCheck_TwoToolsFix';
import START_NOW from '@salesforce/label/c.Core_RollupBuilder_StartNow';
import RUN_TONIGHT from '@salesforce/label/c.Core_RollupBuilder_RunTonight';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import DELETE_ROLLUP from '@salesforce/label/c.Core_Find_Delete';
import EXPORT_ROLLUPS from '@salesforce/label/c.Core_RollupBuilder_Export';
import EXPORT_SELECT from '@salesforce/label/c.Core_RollupBuilder_ExportSelect';
import IMPORT_FILE from '@salesforce/label/c.Core_RollupBuilder_ImportFile';
import IMPORT_COLUMN from '@salesforce/label/c.Core_EraseAction_ColumnAction';
import IMPORT_APPLY from '@salesforce/label/c.Core_RollupBuilder_ImportApply';
import IMPORT_WILL_CREATE from '@salesforce/label/c.Core_RollupBuilder_ImportWillCreate';
import IMPORT_WILL_UPDATE from '@salesforce/label/c.Core_RollupBuilder_ImportWillUpdate';
import IMPORT_CREATED from '@salesforce/label/c.Core_Import_ResultCreated';
import IMPORT_UPDATED from '@salesforce/label/c.Core_Import_ResultUpdated';
import IMPORT_REFUSED from '@salesforce/label/c.Core_RollupBuilder_ImportRefused';
import turnOnSwitchingOffDlrs from '@salesforce/apex/RollupController.turnOnSwitchingOffDlrs';
import DLRS_CONFIRM_TITLE from '@salesforce/label/c.Core_RollupBuilder_DlrsConfirmTitle';
import COLUMN_STATUS from '@salesforce/label/c.Core_ImportRow_StatusLabel';
import SEARCH from '@salesforce/label/c.Core_RollupEase_Search';
import GROUP from '@salesforce/label/c.Core_Format_Parenthetical';
import DELETE_HEADING from '@salesforce/label/c.Core_RollupEase_DeleteHeading';
import DELETE_CHOICE from '@salesforce/label/c.Core_RollupEase_DeleteChoice';
import DELETE_KEEP from '@salesforce/label/c.Core_RollupEase_DeleteKeep';
import DELETE_CLEAR from '@salesforce/label/c.Core_RollupEase_DeleteClear';
import { bodyMessage } from 'c/findCsv';
import { iconFor } from 'c/barnIcons';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

/** The status vocabulary word for each recalculation state in the Status column (U6). */
const STATUS_TONE = {
  failed: 'error',
  waiting: 'pending',
  running: 'running',
  off: 'off',
  clear: 'success'
};

/** The words for each import outcome, before saving and after (ADR-0136). */
const OUTCOMES = {
  preview: {
    created: IMPORT_WILL_CREATE,
    updated: IMPORT_WILL_UPDATE,
    refused: IMPORT_REFUSED,
    get notReached() {
      return helpText('Rollups', 'Core_RollupBuilder_ImportNotReached');
    }
  },
  saved: {
    created: IMPORT_CREATED,
    updated: IMPORT_UPDATED,
    refused: IMPORT_REFUSED,
    get notReached() {
      return helpText('Rollups', 'Core_RollupBuilder_ImportNotReached');
    }
  }
};

/** A chosen file's text, read in the browser. */
function readText(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = () => reject(reader.error);
    reader.readAsText(file);
  });
}

/**
 * The Rollups page of the BarnCRM Settings console.
 *
 * It shows every total BarnCRM keeps up to date, what each one counts, when it was last
 * calculated, and whether the nightly run is scheduled. An administrator can switch a rollup off,
 * change when it is recalculated, and recalculate one on its own or all of them at once. It never
 * shows the vendored engine's own configuration, which is the whole point of ADR-0015.
 */
export default class RollupDefinitions extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded('Rollups');

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Rollups').then(() => {
        this.helpReady = true;
      });
    }
  }

  /**
   * True inside the Rollup Builder, which adds New, Edit, Copy and Delete and listens for `new`,
   * `edit` and `copy` (with `detail.recordId`). On the settings page the list links to the Builder.
   */
  @api builder = false;

  icons = { rollups: iconFor('Rollup_Builder') };

  labels = {
    get dropHint() {
      return helpText('Rollups', 'Core_Rollups_ImportDropHint');
    },
    newRollup: NEW_ROLLUP,
    edit: EDIT,
    copy: COPY,
    openBuilder: OPEN_BUILDER,
    get workingHours() {
      return helpText('Rollups', 'Core_RollupBuilder_EstimateWorkingHours');
    },
    startNow: START_NOW,
    runTonight: RUN_TONIGHT,
    cancel: CANCEL,
    deleteRollup: DELETE_ROLLUP,
    get deleteShipped() {
      return helpText('Rollups', 'Core_RollupBuilder_DeleteShipped');
    },
    get deleted() {
      return helpText('Rollups', 'Core_RollupBuilder_Deleted');
    },
    exportRollups: EXPORT_ROLLUPS,
    exportSelect: EXPORT_SELECT,
    importFile: IMPORT_FILE,
    importColumn: IMPORT_COLUMN,
    importApply: IMPORT_APPLY,
    title: TITLE,
    get intro() {
      return helpText('Rollups', 'Core_Rollups_PageIntro');
    },
    columnRollup: COLUMN_ROLLUP,
    columnCounts: COLUMN_COUNTS,
    countsSeparatedBy: COUNTS_SEPARATED_BY,
    columnMode: COLUMN_MODE,
    columnActive: COLUMN_ACTIVE,
    columnLastCalculated: COLUMN_LAST_CALCULATED,
    recalculate: RECALCULATE,
    recalculateAll: RECALCULATE_ALL,
    get recalculateStarted() {
      return helpText('Rollups', 'Core_Rollups_RecalculateStarted');
    },
    scheduleNightly: SCHEDULE_NIGHTLY,
    get scheduleActive() {
      return helpText('Rollups', 'Core_Rollups_ScheduleActive');
    },
    get scheduleMissing() {
      return helpText('Rollups', 'Core_Rollups_ScheduleMissing');
    },
    stopSchedule: STOP_SCHEDULE,
    restoreDefaults: RESTORE_DEFAULTS,
    get emptyList() {
      return helpText('Rollups', 'Core_Rollups_EmptyList');
    },
    neverCalculated: NEVER_CALCULATED,
    freshnessTitle: FRESHNESS_TITLE,
    freshnessStale: FRESHNESS_STALE,
    get readOnly() {
      return helpText('Rollups', 'Core_Rollups_ReadOnly');
    },
    columnStatus: COLUMN_STATUS,
    search: SEARCH,
    get searchHelp() {
      return helpText('Rollups', 'Core_RollupEase_SearchHelp');
    },
    get noMatches() {
      return helpText('Rollups', 'Core_RollupEase_NoMatches');
    },
    deleteHeading: DELETE_HEADING,
    deleteChoice: DELETE_CHOICE
  };

  /** What the administrator typed to find a rollup (U12). */
  searchTerm = '';

  /** The rollup the Delete panel asks about, and whether its values are cleared (U11). */
  deleting;
  deleteChoice = 'keep';

  page;
  errorMessage;
  noticeMessage;
  busy = false;
  wiredPageResult;
  /** What Recalculate all will go through, shown before it starts (S12). */
  estimate;
  /** The admin-made rollups ticked for Export; none ticked exports all of them. */
  selectedIds = [];
  /** The file being imported, kept until Import these rollups or Cancel. */
  importText;
  /** What the import will do, or did, to each rollup in the file. */
  importRows;

  @wire(getPage)
  wiredPage(result) {
    this.wiredPageResult = result;
    if (result.data) {
      this.page = result.data;
      this.errorMessage = undefined;
    } else if (result.error) {
      this.errorMessage = bodyMessage(
        result.error,
        helpText('Rollups', 'Core_Rollups_UnexpectedError')
      );
    }
  }

  get canManage() {
    return canManageSettings === true;
  }

  get isReadOnly() {
    return !this.canManage;
  }

  get controlsDisabled() {
    return this.isReadOnly || this.busy;
  }

  /** The modes by the names an administrator reads (Instantly, Every night, Both (recommended)). */
  get modeOptions() {
    if (this.page && this.page.modeOptions) {
      return this.page.modeOptions.map((option) => ({ label: option.label, value: option.value }));
    }
    const modes = this.page && this.page.modes ? this.page.modes : [];
    return modes.map((mode) => ({ label: mode, value: mode }));
  }

  /** One row per rollup, with the values the table shows worked out here rather than in markup. */
  get rows() {
    const rollups = this.page && this.page.rollups ? this.page.rollups : [];
    return rollups.map((rollup) => ({
      ...rollup,
      counts: this.countsText(rollup),
      target: `${rollup.targetObject}.${rollup.targetField}`,
      hasLastCalculated: !!rollup.lastCalculated,
      exportable: this.builder && !rollup.packageDefault,
      selected: this.selectedIds.includes(rollup.recordId),
      statusTone: STATUS_TONE[rollup.statusLevel] || 'neutral',
      conflicts: (rollup.conflicts || []).map((text, index) => ({ key: String(index), text }))
    }));
  }

  /** The rows the search finds: by name, description, sentence, or object and field names. */
  get shownRows() {
    const term = (this.searchTerm || '').trim().toLowerCase();
    if (!term) {
      return this.rows;
    }
    return this.rows.filter((row) =>
      [row.name, row.description, row.sentence, row.counts, row.target, row.targetObjectLabel]
        .filter(Boolean)
        .some((text) => text.toLowerCase().includes(term))
    );
  }

  /** The rows found, grouped by the object that shows the total, groups by name (U12). */
  get groups() {
    const byKey = new Map();
    for (const row of this.shownRows) {
      const name = row.targetObjectLabel || row.targetObject || '';
      if (!byKey.has(name)) {
        byKey.set(name, []);
      }
      byKey.get(name).push(row);
    }
    return [...byKey.keys()]
      .sort((one, two) => one.localeCompare(two))
      .map((name) => ({
        key: name,
        heading: GROUP.replace('{0}', name).replace('{1}', String(byKey.get(name).length)),
        rows: byKey.get(name)
      }));
  }

  get hasRows() {
    return this.shownRows.length > 0;
  }

  get isEmpty() {
    return !!this.page && this.rows.length === 0;
  }

  /** Something was searched for and nothing matches. */
  get noMatches() {
    return this.rows.length > 0 && !this.hasRows;
  }

  get hasAnyRollup() {
    return this.rows.length > 0;
  }

  get rollupCount() {
    return this.rows.length;
  }

  get activeCount() {
    return this.rows.filter((row) => row.active).length;
  }

  handleSearch(event) {
    this.searchTerm = event.detail.value;
  }

  get isScheduled() {
    return !!(this.page && this.page.scheduled);
  }

  get scheduleMessage() {
    return this.isScheduled
      ? this.labels.scheduleActive.replace('{0}', this.page.nightlyTime || '')
      : this.labels.scheduleMissing;
  }

  get scheduleButtonLabel() {
    return this.isScheduled ? this.labels.stopSchedule : this.labels.scheduleNightly;
  }

  get lastCalculated() {
    return this.page ? this.page.lastCalculated : undefined;
  }

  get isStale() {
    return !!(this.page && this.page.stale);
  }

  get hasError() {
    return !!this.errorMessage;
  }

  get hasNotice() {
    return !!this.noticeMessage;
  }

  /**
   * What a rollup counts, by the calculation's own name: "Sum Amount__c on Gift__c", and for a
   * text list what separates its values: "Text list Name on Program__c, separated by semicolon".
   */
  countsText(rollup) {
    const aggregate = rollup.aggregateLabel || rollup.aggregate || '';
    const field = rollup.sourceField ? ` ${rollup.sourceField}` : '';
    const counts = `${aggregate}${field} on ${rollup.sourceObject}`;
    if (!rollup.delimiterLabel) {
      return counts;
    }
    const separator = this.labels.countsSeparatedBy.replace(
      '{0}',
      rollup.delimiterLabel.toLowerCase()
    );
    return `${counts}, ${separator}`;
  }

  async handleActiveToggle(event) {
    const definitionId = event.target.dataset.id;
    const active = event.target.checked;
    const input = event.target;
    const before = !active;
    const revert = () => {
      input.checked = before;
    };
    const rollup = (this.page.rollups || []).find((item) => item.recordId === definitionId);
    // An active DLRS rollup fills the same field (R-R16): turn on only on the admin's word.
    if (active && rollup && rollup.otherToolConflict) {
      const confirmed = await LightningConfirm.open({
        label: DLRS_CONFIRM_TITLE,
        message: `${rollup.otherToolConflict} ${helpText('Rollups', 'Core_RollupBuilder_DlrsConfirmQuestion')}`,
        theme: 'warning'
      });
      if (!confirmed) {
        revert();
        return undefined;
      }
      return this.runAction(turnOnSwitchingOffDlrs({ definitionId }), revert);
    }
    return this.runAction(setActive({ definitionId, active }), revert);
  }

  handleModeChange(event) {
    const definitionId = event.target.dataset.id;
    const mode = event.detail.value;
    this.runAction(setMode({ definitionId, mode }));
  }

  handleRecalculate(event) {
    const definitionId = event.target.dataset.id;
    this.runAction(recalculate({ definitionId }), undefined, this.labels.recalculateStarted);
  }

  /** Says how many records and how long first, and offers tonight instead (ADR decision 12). */
  handleRecalculateAll() {
    this.busy = true;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    estimateFullRun()
      .then((estimate) => {
        this.estimate = estimate;
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, helpText('Rollups', 'Core_Rollups_UnexpectedError'));
      })
      .finally(() => {
        this.busy = false;
      });
  }

  handleStartNow() {
    this.estimate = undefined;
    this.runAction(recalculateAll(), undefined, this.labels.recalculateStarted);
  }

  handleRunTonight() {
    this.estimate = undefined;
    this.busy = true;
    runTonight()
      .then((notice) => {
        this.noticeMessage = notice;
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, helpText('Rollups', 'Core_Rollups_UnexpectedError'));
      })
      .finally(() => {
        this.busy = false;
        this.refreshPage();
      });
  }

  handleCancelEstimate() {
    this.estimate = undefined;
  }

  handleSchedule() {
    this.runAction(setSchedule({ scheduled: !this.isScheduled }));
  }

  handleRestoreDefaults() {
    this.runAction(restoreDefaults());
  }

  handleNew() {
    this.dispatchEvent(new CustomEvent('new'));
  }

  handleEdit(event) {
    this.dispatchEvent(new CustomEvent('edit', { detail: { recordId: event.target.dataset.id } }));
  }

  handleCopy(event) {
    this.dispatchEvent(new CustomEvent('copy', { detail: { recordId: event.target.dataset.id } }));
  }

  /**
   * Opens the Delete This Rollup panel for an admin-made rollup (ADR-0136, U11): it asks whether
   * to keep the values the rollup wrote (the default) or clear them. A shipped one is not sent
   * to the server: the reason is shown here, the same words the server would use (R-R6).
   */
  handleDelete(event) {
    const definitionId = event.target.dataset.id;
    const rollup = (this.page.rollups || []).find((item) => item.recordId === definitionId);
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    if (!rollup) {
      return;
    }
    if (rollup.packageDefault) {
      this.errorMessage = this.labels.deleteShipped;
      return;
    }
    this.deleting = { recordId: rollup.recordId, name: rollup.name };
    this.deleteChoice = 'keep';
  }

  get deleteQuestion() {
    return this.deleting
      ? helpText('Rollups', 'Core_RollupEase_DeleteQuestion').replace('{0}', this.deleting.name)
      : '';
  }

  get deleteOptions() {
    return [
      { label: DELETE_KEEP, value: 'keep' },
      { label: DELETE_CLEAR, value: 'clear' }
    ];
  }

  handleDeleteChoice(event) {
    this.deleteChoice = event.detail.value;
  }

  handleCancelDelete() {
    this.deleting = undefined;
  }

  /** Deletes the rollup the panel asks about, keeping or clearing its values as chosen. */
  handleConfirmDelete() {
    const definitionId = this.deleting.recordId;
    const clearValues = this.deleteChoice === 'clear';
    this.deleting = undefined;
    return this.runAction(
      deleteRollup({ definitionId, clearValues }),
      undefined,
      clearValues ? helpText('Rollups', 'Core_RollupEase_DeletedCleared') : this.labels.deleted
    );
  }

  handleSelect(event) {
    const definitionId = event.target.dataset.id;
    const others = this.selectedIds.filter((id) => id !== definitionId);
    this.selectedIds = event.target.checked ? [...others, definitionId] : others;
  }

  /** Downloads the ticked rollups, or every one an administrator made, as a file (ADR-0136). */
  handleExport() {
    this.busy = true;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    return exportDefinitions({ definitionIds: this.selectedIds })
      .then((text) => {
        const link = document.createElement('a');
        link.href = `data:application/json;charset=utf-8,${encodeURIComponent(text)}`;
        link.download = 'barncrm-rollups.json';
        link.click();
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, helpText('Rollups', 'Core_Rollups_UnexpectedError'));
      })
      .finally(() => {
        this.busy = false;
      });
  }

  /** Reads the chosen file here and asks the server what importing it would do. */
  handleImportFile(event) {
    const file = event.detail.files && event.detail.files[0];
    if (!file) {
      return undefined;
    }
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    this.importRows = undefined;
    return readText(file).then((text) => {
      this.importText = text;
      return this.runImport(false);
    });
  }

  handleApplyImport() {
    return this.runImport(true);
  }

  handleCancelImport() {
    this.importText = undefined;
    this.importRows = undefined;
  }

  get importApplyDisabled() {
    return (
      this.controlsDisabled ||
      !(this.importRows || []).some((row) => row.outcome === 'created' || row.outcome === 'updated')
    );
  }

  runImport(save) {
    this.busy = true;
    const words = save ? OUTCOMES.saved : OUTCOMES.preview;
    return importDefinitions({ fileText: this.importText, save })
      .then((rows) => {
        this.importRows = rows.map((row, index) => ({
          ...row,
          key: `${index}-${row.definitionKey}`,
          name: row.name || row.definitionKey,
          text: row.reason ? `${words[row.outcome]}: ${row.reason}` : words[row.outcome]
        }));
        if (save) {
          this.importText = undefined;
          this.noticeMessage = helpText('Rollups', 'Core_RollupBuilder_ImportDone');
        }
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, helpText('Rollups', 'Core_Rollups_UnexpectedError'));
        this.importText = undefined;
      })
      .finally(() => {
        this.busy = false;
        if (save) {
          this.refreshPage();
        }
      });
  }

  handleOpenBuilder() {
    this[NavigationMixin.Navigate]({
      type: 'standard__navItemPage',
      attributes: { apiName: this.page.builderTabApiName }
    });
  }

  get showBuilderLink() {
    return !this.builder && !!this.page && !!this.page.builderTabApiName;
  }

  /** Reads the list again, after the Builder saved a rollup. */
  @api
  refresh() {
    return this.refreshPage();
  }

  runAction(promise, revert, notice) {
    this.busy = true;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    return promise
      .then((page) => {
        this.page = page;
        if (notice) {
          this.noticeMessage = notice;
        }
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, helpText('Rollups', 'Core_Rollups_UnexpectedError'));
        if (revert) {
          revert();
        }
      })
      .finally(() => {
        this.busy = false;
        this.refreshPage();
      });
  }

  refreshPage() {
    if (this.wiredPageResult) {
      return refreshApex(this.wiredPageResult);
    }
    return Promise.resolve();
  }
}
