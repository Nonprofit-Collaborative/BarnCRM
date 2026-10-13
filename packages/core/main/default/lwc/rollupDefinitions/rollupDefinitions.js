import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
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

import TITLE from '@salesforce/label/c.Core_Rollups_PageTitle';
import INTRO from '@salesforce/label/c.Core_Rollups_PageIntro';
import COLUMN_ROLLUP from '@salesforce/label/c.Core_Rollups_ColumnRollup';
import COLUMN_COUNTS from '@salesforce/label/c.Core_Rollups_ColumnCounts';
import COUNTS_SEPARATED_BY from '@salesforce/label/c.Core_Rollups_CountsSeparatedBy';
import COLUMN_TARGET from '@salesforce/label/c.Core_Rollups_ColumnTarget';
import COLUMN_MODE from '@salesforce/label/c.Core_Rollups_ColumnMode';
import COLUMN_ACTIVE from '@salesforce/label/c.Core_Rollups_ColumnActive';
import COLUMN_LAST_CALCULATED from '@salesforce/label/c.Core_Rollups_ColumnLastCalculated';
import RECALCULATE from '@salesforce/label/c.Core_Rollups_Recalculate';
import RECALCULATE_ALL from '@salesforce/label/c.Core_Rollups_RecalculateAll';
import RECALCULATE_STARTED from '@salesforce/label/c.Core_Rollups_RecalculateStarted';
import SCHEDULE_NIGHTLY from '@salesforce/label/c.Core_Rollups_ScheduleNightly';
import SCHEDULE_ACTIVE from '@salesforce/label/c.Core_Rollups_ScheduleActive';
import SCHEDULE_MISSING from '@salesforce/label/c.Core_Rollups_ScheduleMissing';
import STOP_SCHEDULE from '@salesforce/label/c.Core_Rollups_StopSchedule';
import RESTORE_DEFAULTS from '@salesforce/label/c.Core_Rollups_RestoreDefaults';
import EMPTY_LIST from '@salesforce/label/c.Core_Rollups_EmptyList';
import NEVER_CALCULATED from '@salesforce/label/c.Core_Rollups_NeverCalculated';
import FRESHNESS_TITLE from '@salesforce/label/c.Core_Rollups_FreshnessTitle';
import FRESHNESS_STALE from '@salesforce/label/c.Core_Rollups_FreshnessStale';
import READ_ONLY from '@salesforce/label/c.Core_Rollups_ReadOnly';
import UNEXPECTED_ERROR from '@salesforce/label/c.Core_Rollups_UnexpectedError';
import NEW_ROLLUP from '@salesforce/label/c.Core_RollupBuilder_New';
import EDIT from '@salesforce/label/c.Core_RollupBuilder_Edit';
import COPY from '@salesforce/label/c.Core_RollupBuilder_Copy';
import OPEN_BUILDER from '@salesforce/label/c.Core_RollupBuilder_Open';
import WORKING_HOURS from '@salesforce/label/c.Core_RollupBuilder_EstimateWorkingHours';
import START_NOW from '@salesforce/label/c.Core_RollupBuilder_StartNow';
import RUN_TONIGHT from '@salesforce/label/c.Core_RollupBuilder_RunTonight';
import CANCEL from '@salesforce/label/c.Core_RollupBuilder_Cancel';

/**
 * The Rollups page of the BarnCRM Settings console.
 *
 * It shows every total BarnCRM keeps up to date, what each one counts, when it was last
 * calculated, and whether the nightly run is scheduled. An administrator can switch a rollup off,
 * change when it is recalculated, and recalculate one on its own or all of them at once. It never
 * shows the vendored engine's own configuration, which is the whole point of ADR-0015.
 */
export default class RollupDefinitions extends NavigationMixin(LightningElement) {
  /**
   * True inside the Rollup Builder, which adds New, Edit and Copy and listens for `new`, `edit`
   * and `copy` (with `detail.recordId`). On the settings page the list links to the Builder.
   */
  @api builder = false;

  labels = {
    newRollup: NEW_ROLLUP,
    edit: EDIT,
    copy: COPY,
    openBuilder: OPEN_BUILDER,
    workingHours: WORKING_HOURS,
    startNow: START_NOW,
    runTonight: RUN_TONIGHT,
    cancel: CANCEL,
    title: TITLE,
    intro: INTRO,
    columnRollup: COLUMN_ROLLUP,
    columnCounts: COLUMN_COUNTS,
    countsSeparatedBy: COUNTS_SEPARATED_BY,
    columnTarget: COLUMN_TARGET,
    columnMode: COLUMN_MODE,
    columnActive: COLUMN_ACTIVE,
    columnLastCalculated: COLUMN_LAST_CALCULATED,
    recalculate: RECALCULATE,
    recalculateAll: RECALCULATE_ALL,
    recalculateStarted: RECALCULATE_STARTED,
    scheduleNightly: SCHEDULE_NIGHTLY,
    scheduleActive: SCHEDULE_ACTIVE,
    scheduleMissing: SCHEDULE_MISSING,
    stopSchedule: STOP_SCHEDULE,
    restoreDefaults: RESTORE_DEFAULTS,
    emptyList: EMPTY_LIST,
    neverCalculated: NEVER_CALCULATED,
    freshnessTitle: FRESHNESS_TITLE,
    freshnessStale: FRESHNESS_STALE,
    readOnly: READ_ONLY
  };

  page;
  errorMessage;
  noticeMessage;
  busy = false;
  wiredPageResult;
  /** What Recalculate all will go through, shown before it starts (S12). */
  estimate;

  @wire(getPage)
  wiredPage(result) {
    this.wiredPageResult = result;
    if (result.data) {
      this.page = result.data;
      this.errorMessage = undefined;
    } else if (result.error) {
      this.errorMessage = this.messageFrom(result.error);
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
      hasLastCalculated: !!rollup.lastCalculated
    }));
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get isEmpty() {
    return !!this.page && !this.hasRows;
  }

  get isScheduled() {
    return !!(this.page && this.page.scheduled);
  }

  get scheduleMessage() {
    return this.isScheduled ? this.labels.scheduleActive : this.labels.scheduleMissing;
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

  handleActiveToggle(event) {
    const definitionId = event.target.dataset.id;
    const active = event.target.checked;
    const input = event.target;
    const before = !active;
    this.runAction(setActive({ definitionId, active }), () => {
      input.checked = before;
    });
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
        this.errorMessage = this.messageFrom(error);
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
        this.errorMessage = this.messageFrom(error);
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
        this.errorMessage = this.messageFrom(error);
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

  messageFrom(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    return UNEXPECTED_ERROR;
  }
}
