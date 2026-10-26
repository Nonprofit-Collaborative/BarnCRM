import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
// Bare, and correctly so: a custom permission defined in the same package resolves without a
// namespace prefix.
import canManageSettings from '@salesforce/customPermission/Manage_BarnCRM_Settings';
import getSwap from '@salesforce/apex/SeasonalAddressController.getSwap';
import runNow from '@salesforce/apex/SeasonalAddressController.runNow';

import TITLE from '@salesforce/label/c.Core_SeasonalAddress_PageTitle';
import INTRO from '@salesforce/label/c.Core_SeasonalAddress_PageIntro';
import HUB_TITLE from '@salesforce/label/c.Core_SeasonalAddress_HubTitle';
import NEVER_RUN from '@salesforce/label/c.Core_SeasonalAddress_NeverRun';
import NOT_SCHEDULED from '@salesforce/label/c.Core_SeasonalAddress_NotScheduled';
import SCHEDULE_ACTIVE from '@salesforce/label/c.Core_SeasonalAddress_ScheduleActive';
import SWITCHED_OFF from '@salesforce/label/c.Core_SeasonalAddress_SwitchedOff';
import RUN_NOW from '@salesforce/label/c.Core_SeasonalAddress_RunNow';
import RUN_NOW_STARTED from '@salesforce/label/c.Core_SeasonalAddress_RunNowStarted';
import STALE from '@salesforce/label/c.Core_SeasonalAddress_Stale';
import READ_ONLY from '@salesforce/label/c.Core_SeasonalAddress_ReadOnly';
import UNEXPECTED_ERROR from '@salesforce/label/c.Core_SeasonalAddress_UnexpectedError';

/**
 * The seasonal address swap panel on the Addresses page of the BarnCRM Settings console.
 *
 * It exists because a nightly job whose last run nobody can see is a job nobody trusts. It
 * answers, in this order, whether the job is switched on, when it last ran, and what it did,
 * and it carries the Run now button. The job is scheduled and stopped by the Seasonal Addresses
 * switch above it in the same section (saved with the console's own Save), so scheduling Apex
 * is never a Setup task, which is the thing this product does not ask an administrator to do.
 */
export default class SeasonalAddressJob extends LightningElement {
  labels = {
    title: TITLE,
    intro: INTRO,
    lastRunTitle: HUB_TITLE,
    neverRun: NEVER_RUN,
    notScheduled: NOT_SCHEDULED,
    switchedOff: SWITCHED_OFF,
    scheduleActive: SCHEDULE_ACTIVE,
    runNow: RUN_NOW,
    stale: STALE,
    readOnly: READ_ONLY
  };

  swap;
  errorMessage;
  noticeMessage;
  busy = false;
  wiredSwapResult;

  @wire(getSwap)
  wiredSwap(result) {
    this.wiredSwapResult = result;
    if (result.data) {
      this.swap = result.data;
      this.errorMessage = undefined;
    } else if (result.error) {
      this.errorMessage = UNEXPECTED_ERROR;
    }
  }

  /**
   * The console calls this after a save, because this panel stays mounted: saving the Seasonal
   * Addresses switch schedules or stops the job, and the status line should say so at once.
   */
  @api
  refresh() {
    this.errorMessage = undefined;
    return this.wiredSwapResult ? refreshApex(this.wiredSwapResult) : Promise.resolve();
  }

  get isScheduled() {
    return !!(this.swap && this.swap.scheduled);
  }

  get isEnabled() {
    return !!(this.swap && this.swap.enabled);
  }

  get isStale() {
    return !!(this.swap && this.swap.stale);
  }

  get lastRun() {
    return this.swap ? this.swap.lastRun : undefined;
  }

  get lastRunSummary() {
    return this.swap ? this.swap.lastRunSummary : undefined;
  }

  get hasLastRun() {
    return !!this.lastRun;
  }

  get nextRunAt() {
    return this.swap ? this.swap.nextRunAt : undefined;
  }

  get hasNextRun() {
    return !!this.nextRunAt;
  }

  get scheduleMessage() {
    if (!this.isEnabled && !this.isScheduled) {
      return this.labels.switchedOff;
    }
    return this.isScheduled ? this.labels.scheduleActive : this.labels.notScheduled;
  }

  /**
   * The permission is read from the platform rather than from the payload, so the button is
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

  handleRunNow() {
    this.runAction(runNow(), RUN_NOW_STARTED);
  }

  async runAction(promise, notice) {
    this.busy = true;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    try {
      this.swap = await promise;
      this.noticeMessage = notice;
      if (this.wiredSwapResult) {
        await refreshApex(this.wiredSwapResult);
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
