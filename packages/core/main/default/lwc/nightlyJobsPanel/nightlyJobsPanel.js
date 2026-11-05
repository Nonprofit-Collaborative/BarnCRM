import { LightningElement, api } from 'lwc';
// Bare, and correctly so: a custom permission defined in the same package resolves without a
// namespace prefix.
import canManageSettings from '@salesforce/customPermission/Manage_BarnCRM_Settings';
import getPanel from '@salesforce/apex/NightlyJobsController.getPanel';
import schedule from '@salesforce/apex/NightlyJobsController.schedule';

import TITLE from '@salesforce/label/c.Core_NightlyJobs_Title';
import JOB from '@salesforce/label/c.Core_NightlyJobs_ColumnJob';
import TIME from '@salesforce/label/c.Core_NightlyJobs_ColumnTime';
import SCHEDULE from '@salesforce/label/c.Core_NightlyJobs_ScheduleButton';
import STATUS from '@salesforce/label/c.Core_ImportRow_StatusLabel';
import LAST_RUN from '@salesforce/label/c.Core_ErrorDigest_LastRunTitle';
import RESULT from '@salesforce/label/c.Core_Find_Result';
import ON from '@salesforce/label/c.Core_Feature_On';
import OFF from '@salesforce/label/c.Core_Feature_Off';
import UNEXPECTED_ERROR from '@salesforce/label/c.Core_UnexpectedError';
import { bodyMessage } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

/** Minutes after midnight as the reader writes a time of day, for example 1:15 AM. */
export function timeOfDay(minute) {
  const at = new Date(2000, 0, 1, Math.floor(minute / 60), minute % 60);
  return at.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
}

/**
 * The Nightly Jobs panel on the General page of the BarnCRM Settings console (ADR-0166
 * nightly-job-dispatcher): the one nightly schedule, and every step in the order the run takes
 * it, with its time, whether it is on, and how it last ran. Each step is switched on and off on
 * its own page; the only action here is scheduling the run when it is not scheduled.
 */
export default class NightlyJobsPanel extends LightningElement {
  helpReady = isHelpLoaded('Core');
  panel;
  errorMessage;
  noticeMessage;
  busy = false;

  labels = {
    title: TITLE,
    get intro() {
      return helpText('Core', 'Core_NightlyJobs_Intro');
    },
    job: JOB,
    time: TIME,
    status: STATUS,
    lastRun: LAST_RUN,
    result: RESULT,
    schedule: SCHEDULE
  };

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
    this.refresh();
  }

  /** The console calls this after a save; a step's switch may have changed on another page. */
  @api
  refresh() {
    this.errorMessage = undefined;
    return getPanel()
      .then((result) => {
        this.panel = result;
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, UNEXPECTED_ERROR);
      });
  }

  get rows() {
    return ((this.panel && this.panel.steps) || []).map((step) => ({
      key: step.key,
      label: step.label,
      time: timeOfDay(step.minute),
      state: step.isOn ? ON : OFF,
      stateStatus: step.isOn ? 'on' : 'off',
      lastStarted: step.lastStarted,
      outcome: step.outcome,
      outcomeStatus: step.outcomeStatus,
      message: step.message
    }));
  }

  get hasLastRun() {
    return !!(this.panel && this.panel.lastRunStarted);
  }

  get scheduleMessage() {
    return this.panel && this.panel.scheduled
      ? helpText('Core', 'Core_NightlyJobs_Scheduled')
      : helpText('Core', 'Core_NightlyJobs_NotScheduled');
  }

  /** Read from the platform so the button never flickers; the controller checks it again. */
  get showSchedule() {
    return !!this.panel && !this.panel.scheduled && canManageSettings === true;
  }

  async handleSchedule() {
    this.busy = true;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    try {
      this.panel = await schedule();
      this.noticeMessage = helpText('Core', 'Core_NightlyJobs_ScheduledNotice');
    } catch (error) {
      this.errorMessage = bodyMessage(error, UNEXPECTED_ERROR);
    } finally {
      this.busy = false;
    }
  }
}
