import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getView from '@salesforce/apex/FieldUtilizationController.getView';
import getResults from '@salesforce/apex/FieldUtilizationController.getResults';
import saveObjects from '@salesforce/apex/FieldUtilizationController.saveObjects';
import setSchedule from '@salesforce/apex/FieldUtilizationController.setSchedule';
import runNow from '@salesforce/apex/FieldUtilizationController.runNow';

import TITLE from '@salesforce/label/c.Core_FieldUtilization_PageTitle';
import INTRO from '@salesforce/label/c.Core_FieldUtilization_PageIntro';
import LAST_RUN_TITLE from '@salesforce/label/c.Core_FieldUtilization_LastRunTitle';
import NEVER_RUN from '@salesforce/label/c.Core_FieldUtilization_NeverRun';
import NOT_SCHEDULED from '@salesforce/label/c.Core_FieldUtilization_NotScheduled';
import SCHEDULE_ACTIVE from '@salesforce/label/c.Core_FieldUtilization_ScheduleActive';
import SCHEDULE_BUTTON from '@salesforce/label/c.Core_FieldUtilization_ScheduleButton';
import STOP_BUTTON from '@salesforce/label/c.Core_FieldUtilization_StopButton';
import RUN_NOW from '@salesforce/label/c.Core_FieldUtilization_RunNow';
import RUN_NOW_STARTED from '@salesforce/label/c.Core_FieldUtilization_RunNowStarted';
import CHOOSE_TITLE from '@salesforce/label/c.Core_FieldUtilization_ChooseTitle';
import CHOOSE_LABEL from '@salesforce/label/c.Core_FieldUtilization_ChooseLabel';
import AVAILABLE from '@salesforce/label/c.Core_FieldUtilization_Available';
import COUNTED from '@salesforce/label/c.Core_FieldUtilization_Counted';
import SAVE from '@salesforce/label/c.Core_FieldUtilization_Save';
import SAVED from '@salesforce/label/c.Core_FieldUtilization_Saved';
import RESULTS_TITLE from '@salesforce/label/c.Core_FieldUtilization_ResultsTitle';
import SHOW_RESULTS_FOR from '@salesforce/label/c.Core_FieldUtilization_ShowResultsFor';
import NO_RESULTS from '@salesforce/label/c.Core_FieldUtilization_NoResults';
import COMPARED_WITH from '@salesforce/label/c.Core_FieldUtilization_ComparedWith';
import COL_FIELD from '@salesforce/label/c.Core_FieldUtilization_ColField';
import COL_RECORD_TYPE from '@salesforce/label/c.Core_FieldUtilization_ColRecordType';
import COL_FILLED from '@salesforce/label/c.Core_FieldUtilization_ColFilled';
import COL_WITH_VALUE from '@salesforce/label/c.Core_FieldUtilization_ColWithValue';
import COL_RECORDS from '@salesforce/label/c.Core_FieldUtilization_ColRecords';
import COL_CHANGE from '@salesforce/label/c.Core_FieldUtilization_ColChange';
import COL_SAMPLED from '@salesforce/label/c.Core_FieldUtilization_ColSampled';
import UNEXPECTED_ERROR from '@salesforce/label/c.Core_FieldUtilization_UnexpectedError';

const COLUMNS = [
  { label: COL_FIELD, fieldName: 'fieldLabel', sortable: true },
  { label: COL_RECORD_TYPE, fieldName: 'recordType', sortable: true },
  {
    label: COL_FILLED,
    fieldName: 'share',
    type: 'percent',
    sortable: true,
    typeAttributes: { maximumFractionDigits: 1 }
  },
  { label: COL_WITH_VALUE, fieldName: 'filled', type: 'number', sortable: true },
  { label: COL_RECORDS, fieldName: 'total', type: 'number', sortable: true },
  {
    label: COL_CHANGE,
    fieldName: 'change',
    type: 'number',
    sortable: true,
    typeAttributes: { maximumFractionDigits: 1 }
  },
  { label: COL_SAMPLED, fieldName: 'sampled', type: 'boolean' }
];

/**
 * The Field Utilization page of the BarnCRM Settings console: the weekly count's schedule,
 * the objects it covers, and the latest share of records with each field filled in, with the
 * change since the count before (canonical model Section 29F). Shown only to holders of
 * Manage BarnCRM Settings, which the controller checks again on every change.
 */
export default class FieldUtilization extends LightningElement {
  labels = {
    title: TITLE,
    intro: INTRO,
    lastRunTitle: LAST_RUN_TITLE,
    neverRun: NEVER_RUN,
    runNow: RUN_NOW,
    chooseTitle: CHOOSE_TITLE,
    chooseLabel: CHOOSE_LABEL,
    available: AVAILABLE,
    counted: COUNTED,
    save: SAVE,
    resultsTitle: RESULTS_TITLE,
    showResultsFor: SHOW_RESULTS_FOR,
    noResults: NO_RESULTS,
    comparedWith: COMPARED_WITH
  };

  columns = COLUMNS;
  view;
  selected = [];
  resultsObject;
  rows = [];
  previousTakenAt;
  sortedBy;
  sortedDirection = 'asc';
  errorMessage;
  noticeMessage;
  busy = false;
  wiredViewResult;

  @wire(getView)
  wiredView(result) {
    this.wiredViewResult = result;
    if (result.data) {
      this.applyView(result.data);
      this.errorMessage = undefined;
    } else if (result.error) {
      this.errorMessage = UNEXPECTED_ERROR;
    }
  }

  applyView(view) {
    this.view = view;
    this.selected = [...(view.tracked || [])];
    if (!this.resultsObject && this.selected.length) {
      this.loadResults(this.selected[0]);
    }
  }

  get lastRun() {
    return this.view ? this.view.lastRun : undefined;
  }

  get lastRunSummary() {
    return this.view ? this.view.lastRunSummary : undefined;
  }

  get nextRunAt() {
    return this.view ? this.view.nextRunAt : undefined;
  }

  get isScheduled() {
    return !!(this.view && this.view.scheduled);
  }

  get scheduleMessage() {
    return this.isScheduled ? SCHEDULE_ACTIVE : NOT_SCHEDULED;
  }

  get scheduleButtonLabel() {
    return this.isScheduled ? STOP_BUTTON : SCHEDULE_BUTTON;
  }

  get objectOptions() {
    return this.view && this.view.choosable ? this.view.choosable : [];
  }

  get trackedOptions() {
    const tracked = new Set(this.view && this.view.tracked ? this.view.tracked : []);
    return this.objectOptions.filter((option) => tracked.has(option.value));
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  handleObjectsChange(event) {
    this.selected = event.detail.value;
  }

  handleSave() {
    this.runAction(saveObjects({ objectNames: this.selected }), SAVED);
  }

  handleSchedule() {
    this.runAction(setSchedule({ scheduled: !this.isScheduled }));
  }

  handleRunNow() {
    this.runAction(runNow(), RUN_NOW_STARTED);
  }

  handleResultsObject(event) {
    this.loadResults(event.detail.value);
  }

  handleSort(event) {
    const { fieldName, sortDirection } = event.detail;
    const direction = sortDirection === 'desc' ? -1 : 1;
    const valueOf = (row) => {
      const value = row[fieldName];
      return value === null || value === undefined ? '' : value;
    };
    this.rows = [...this.rows].sort((a, b) => {
      const left = valueOf(a);
      const right = valueOf(b);
      if (left === right) {
        return 0;
      }
      return left > right ? direction : -direction;
    });
    this.sortedBy = fieldName;
    this.sortedDirection = sortDirection;
  }

  async loadResults(objectName) {
    this.resultsObject = objectName;
    this.rows = [];
    this.previousTakenAt = undefined;
    if (!objectName) {
      return;
    }
    try {
      const results = await getResults({ objectName });
      this.previousTakenAt = results.previousTakenAt;
      this.rows = (results.rows || []).map((row) => ({
        ...row,
        share: row.percent === null || row.percent === undefined ? null : row.percent / 100
      }));
    } catch (error) {
      this.errorMessage = this.messageFrom(error);
    }
  }

  async runAction(promise, notice) {
    this.busy = true;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    try {
      this.applyView(await promise);
      this.noticeMessage = notice;
      if (this.wiredViewResult) {
        await refreshApex(this.wiredViewResult);
      }
    } catch (error) {
      this.errorMessage = this.messageFrom(error);
    } finally {
      this.busy = false;
    }
  }

  messageFrom(error) {
    const body = error && error.body;
    return (body && body.message) || UNEXPECTED_ERROR;
  }
}
