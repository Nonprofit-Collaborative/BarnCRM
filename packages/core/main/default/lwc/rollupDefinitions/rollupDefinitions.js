import { LightningElement, wire } from 'lwc';
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

import TITLE from '@salesforce/label/c.Core_Rollups_PageTitle';
import INTRO from '@salesforce/label/c.Core_Rollups_PageIntro';
import COLUMN_ROLLUP from '@salesforce/label/c.Core_Rollups_ColumnRollup';
import COLUMN_COUNTS from '@salesforce/label/c.Core_Rollups_ColumnCounts';
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

/**
 * The Rollups page of the BarnCRM Settings console.
 *
 * It shows every total BarnCRM keeps up to date, what each one counts, when it was last
 * calculated, and whether the nightly run is scheduled. An administrator can switch a rollup off,
 * change when it is recalculated, and recalculate one on its own or all of them at once. It never
 * shows the vendored engine's own configuration, which is the whole point of ADR-0015.
 */
export default class RollupDefinitions extends LightningElement {
  labels = {
    title: TITLE,
    intro: INTRO,
    columnRollup: COLUMN_ROLLUP,
    columnCounts: COLUMN_COUNTS,
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

  countsText(rollup) {
    const aggregate = rollup.aggregate || '';
    const field = rollup.sourceField ? ` ${rollup.sourceField}` : '';
    return `${aggregate}${field} on ${rollup.sourceObject}`;
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

  handleRecalculateAll() {
    this.runAction(recalculateAll(), undefined, this.labels.recalculateStarted);
  }

  handleSchedule() {
    this.runAction(setSchedule({ scheduled: !this.isScheduled }));
  }

  handleRestoreDefaults() {
    this.runAction(restoreDefaults());
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
