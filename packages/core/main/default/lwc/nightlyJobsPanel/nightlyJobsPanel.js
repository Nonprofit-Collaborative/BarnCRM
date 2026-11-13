import { LightningElement, api } from 'lwc';
import LOCALE from '@salesforce/i18n/locale';
// Bare, and correctly so: a custom permission defined in the same package resolves without a
// namespace prefix.
import canManageSettings from '@salesforce/customPermission/Manage_BarnCRM_Settings';
import getPanel from '@salesforce/apex/NightlyJobsController.getPanel';
import schedule from '@salesforce/apex/NightlyJobsController.schedule';
import setStep from '@salesforce/apex/NightlyJobsController.setStep';
import runStep from '@salesforce/apex/NightlyJobsController.runStep';

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
import TURN_ON from '@salesforce/label/c.Core_NightlyJobs_TurnOn';
import TURN_OFF from '@salesforce/label/c.Core_NightlyJobs_TurnOff';
import RUN_NOW from '@salesforce/label/c.Core_NightlyJobs_RunNow';
import ACTIONS from '@salesforce/label/c.Core_Shared_Actions';
import { bodyMessage } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

/**
 * Minutes after midnight as the reader writes a time of day in their Salesforce locale, for
 * example 1:15 AM. A clock time, not an instant: formatted as UTC so no time zone moves it.
 */
/** A step's state: Off, On, or Not Scheduled when it is on but the nightly run is not scheduled. */
function stepState(isOn, scheduled, onLabel, offLabel) {
  if (!isOn) {
    return offLabel;
  }
  return scheduled ? onLabel : helpText('Core', 'Core_NightlyJobs_StateNotScheduled');
}

export function timeOfDay(minute) {
  const at = new Date(Date.UTC(2000, 0, 1, Math.floor(minute / 60), minute % 60));
  return at.toLocaleTimeString(LOCALE, {
    hour: 'numeric',
    minute: '2-digit',
    timeZone: 'UTC'
  });
}

/**
 * The Nightly Jobs panel on the General page of the BarnCRM Settings console (ADR-0166
 * nightly-job-dispatcher): the one nightly schedule, and every module's step in the order the run
 * takes it, with its time, whether it is on, and how it last ran. A manager schedules the run,
 * turns a step with a switch on or off, and starts a step that allows it now (D-200 S6: this one
 * card replaced Giving's Nightly Jobs page).
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
    schedule: SCHEDULE,
    runNow: RUN_NOW,
    actions: ACTIONS,
    get missed() {
      return helpText('Core', 'Core_NightlyJobs_Missed');
    }
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

  /** A step switched on while the run is not scheduled never runs, so it says so, not On. */
  get rows() {
    const scheduled = !!(this.panel && this.panel.scheduled);
    return ((this.panel && this.panel.steps) || []).map((step) => ({
      key: step.key,
      label: step.label,
      time: timeOfDay(step.minute),
      state: stepState(step.isOn, scheduled, ON, OFF),
      stateStatus: !step.isOn ? 'off' : scheduled ? 'on' : 'warning',
      lastStarted: step.lastStarted,
      outcome: step.outcome,
      outcomeStatus: step.outcomeStatus,
      message: step.message,
      hasSwitch: step.hasSwitch === true,
      switchLabel: step.switchedOn ? TURN_OFF : TURN_ON,
      switchedOn: step.switchedOn === true,
      canRunNow: step.canRunNow === true,
      summary: step.summary,
      missed: step.missed === true
    }));
  }

  /** Read from the platform so the buttons never flicker; the controller checks it again. */
  get canManage() {
    return canManageSettings === true;
  }

  handleSwitch(event) {
    const key = event.target.dataset.key;
    const row = this.rows.find((candidate) => candidate.key === key);
    return this.act(
      setStep({ key, turnOn: !(row && row.switchedOn) }),
      helpText('Core', 'Core_NightlyJobs_SwitchSaved')
    );
  }

  handleRunNow(event) {
    return this.act(
      runStep({ key: event.target.dataset.key }),
      helpText('Core', 'Core_NightlyJobs_RunStarted')
    );
  }

  async act(call, notice) {
    this.busy = true;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    try {
      this.panel = await call;
      this.noticeMessage = notice;
    } catch (error) {
      this.errorMessage = bodyMessage(error, UNEXPECTED_ERROR);
    } finally {
      this.busy = false;
    }
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

  handleSchedule() {
    return this.act(schedule(), helpText('Core', 'Core_NightlyJobs_ScheduledNotice'));
  }
}
