import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
// Bare, and correctly so: a custom permission defined in Core resolves without a namespace
// prefix while the namespace is deferred.
import canManageSettings from '@salesforce/customPermission/Manage_BarnCRM_Settings';
import getJobs from '@salesforce/apex/GivingJobsController.getJobs';
import setSchedule from '@salesforce/apex/GivingJobsController.setSchedule';
import runNow from '@salesforce/apex/GivingJobsController.runNow';

import TITLE from '@salesforce/label/c.Giving_NightlyJobs_Title';
import INTRO from '@salesforce/label/c.Giving_NightlyJobs_Intro';
import LAST_RUN_HEADING from '@salesforce/label/c.Giving_NightlyJobs_LastRunHeading';
import NEXT_RUN_HEADING from '@salesforce/label/c.Giving_NightlyJobs_NextRunHeading';
import NEVER_RUN from '@salesforce/label/c.Giving_NightlyJobs_NeverRun';
import NOT_SCHEDULED from '@salesforce/label/c.Giving_NightlyJobs_NotScheduled';
import SCHEDULE_ACTIVE from '@salesforce/label/c.Giving_NightlyJobs_ScheduleActive';
import SCHEDULE_BUTTON from '@salesforce/label/c.Giving_NightlyJobs_ScheduleButton';
import STOP_BUTTON from '@salesforce/label/c.Giving_NightlyJobs_StopButton';
import RUN_NOW from '@salesforce/label/c.Giving_NightlyJobs_RunNow';
import RUN_NOW_STARTED from '@salesforce/label/c.Giving_NightlyJobs_RunNowStarted';
import STALE from '@salesforce/label/c.Giving_NightlyJobs_Stale';
import READ_ONLY from '@salesforce/label/c.Giving_NightlyJobs_ReadOnly';
import UNEXPECTED_ERROR from '@salesforce/label/c.Giving_NightlyJobs_UnexpectedError';
import { bodyMessage } from 'c/findCsv';

/**
 * The Nightly Jobs page for the Giving module, reached from the Giving section of the Nonprofit
 * Settings console (ADR-0020, ADR-0038).
 *
 * It exists because nothing scheduled these jobs in a real org, so no payment was ever marked
 * Overdue, and because a nightly job whose last run nobody can see is a job nobody trusts. It
 * answers, for each job, whether it is switched on, when it last ran and what it did, and it
 * carries the buttons that switch all three on and off.
 */
export default class GivingNightlyJobs extends LightningElement {
  labels = {
    title: TITLE,
    intro: INTRO,
    lastRunHeading: LAST_RUN_HEADING,
    nextRunHeading: NEXT_RUN_HEADING,
    neverRun: NEVER_RUN,
    runNow: RUN_NOW,
    stale: STALE,
    readOnly: READ_ONLY
  };

  view;
  errorMessage;
  noticeMessage;
  busy = false;
  wiredJobsResult;

  @wire(getJobs)
  wiredJobs(result) {
    this.wiredJobsResult = result;
    if (result.data) {
      this.view = result.data;
      this.errorMessage = undefined;
    } else if (result.error) {
      this.errorMessage = UNEXPECTED_ERROR;
    }
  }

  get isScheduled() {
    return !!(this.view && this.view.scheduled);
  }

  get jobs() {
    if (!this.view || !this.view.jobs) {
      return [];
    }
    return this.view.jobs.map((job) => ({
      ...job,
      key: job.name,
      hasLastRun: !!job.lastRun,
      hasSummary: !!job.lastRunSummary
    }));
  }

  get nextRunAt() {
    return this.view ? this.view.nextRunAt : undefined;
  }

  get hasNextRun() {
    return !!this.nextRunAt;
  }

  get scheduleMessage() {
    return this.isScheduled ? SCHEDULE_ACTIVE : NOT_SCHEDULED;
  }

  get scheduleButtonLabel() {
    return this.isScheduled ? STOP_BUTTON : SCHEDULE_BUTTON;
  }

  /**
   * The permission is read from the platform rather than from the payload, so the buttons are
   * disabled before the first round trip finishes rather than flickering from enabled to
   * disabled. The controller checks it again, which is where the real gate is.
   */
  get canManage() {
    return canManageSettings === true;
  }

  get controlsDisabled() {
    return this.busy || !this.canManage;
  }

  get showReadOnlyNote() {
    return !this.canManage;
  }

  handleSchedule() {
    this.runAction(setSchedule({ scheduled: !this.isScheduled }));
  }

  handleRunNow() {
    this.runAction(runNow(), RUN_NOW_STARTED);
  }

  async runAction(promise, notice) {
    this.busy = true;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    try {
      this.view = await promise;
      this.noticeMessage = notice;
      if (this.wiredJobsResult) {
        await refreshApex(this.wiredJobsResult);
      }
    } catch (error) {
      this.errorMessage = bodyMessage(error, UNEXPECTED_ERROR);
    } finally {
      this.busy = false;
    }
  }
}
