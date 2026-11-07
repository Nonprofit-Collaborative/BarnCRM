import { LightningElement } from 'lwc';
import getView from '@salesforce/apex/ReportSubscriptions.getView';
import subscribe from '@salesforce/apex/ReportSubscriptions.subscribe';
import check from '@salesforce/apex/ReportSubscriptions.check';
import { bodyMessage } from 'c/findCsv';
import { helpText } from 'c/barnHelpText';

import TITLE from '@salesforce/label/c.Core_ReportSubscriptions_Title';
import SUBSCRIBE from '@salesforce/label/c.Core_ReportSubscriptions_Subscribe';
import FREQUENCY from '@salesforce/label/c.Core_ReportSubscriptions_Frequency';
import DAILY from '@salesforce/label/c.Core_ReportSubscriptions_Daily';
import WEEKLY from '@salesforce/label/c.Core_ReportSubscriptions_Weekly';
import MONTHLY from '@salesforce/label/c.Core_ReportSubscriptions_Monthly';
import DAY from '@salesforce/label/c.Core_ReportSubscriptions_Day';
import TIME from '@salesforce/label/c.Core_NightlyJobs_ColumnTime';
import SAVE from '@salesforce/label/c.Core_Kit_Save';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';

const POLL_MS = 3000;
const MAX_POLLS = 40;
const WEEKDAY_KEYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
// 1 January 2023 was a Sunday: names come from the browser, in the person's language.
const SUNDAY = Date.UTC(2023, 0, 1);
const DAY_MS = 86400000;

/**
 * Report Subscriptions in Org Optimizer (C-63, D-156, ADR "Duplicate Rules Starter and report
 * subscriptions through the org connection"): BarnCRM's shipped reports, each with Subscribe and
 * a schedule. Saving queues a job that creates or updates the person's own Salesforce report
 * subscription through the org connection; the page polls until it is done. Without the
 * connection each report still opens, where Salesforce's own Subscribe button is.
 */
export default class ReportSubscriptions extends LightningElement {
  view;
  errorMessage;
  editingId;
  savingId;
  results = {};
  form = { frequency: 'weekly', weekday: 'mon', monthDay: 1, hour: 7 };

  labels = {
    title: TITLE,
    subscribe: SUBSCRIBE,
    frequency: FREQUENCY,
    day: DAY,
    time: TIME,
    save: SAVE,
    cancel: CANCEL,
    get intro() {
      return helpText('Core', 'Core_ReportSubscriptions_Intro');
    },
    get openToSubscribe() {
      return helpText('Core', 'Core_ReportSubscriptions_OpenToSubscribe');
    },
    get connectionNeeded() {
      return helpText('Core', 'Core_ReportSubscriptions_ConnectionNeeded');
    },
    get noReports() {
      return helpText('Core', 'Core_ReportSubscriptions_NoReports');
    },
    get saving() {
      return helpText('Core', 'Core_ReportSubscriptions_Saving');
    }
  };

  frequencyOptions = [
    { label: DAILY, value: 'daily' },
    { label: WEEKLY, value: 'weekly' },
    { label: MONTHLY, value: 'monthly' }
  ];

  weekdayOptions = WEEKDAY_KEYS.map((value, index) => ({
    value,
    label: new Date(SUNDAY + index * DAY_MS).toLocaleDateString(undefined, {
      weekday: 'long',
      timeZone: 'UTC'
    })
  }));

  hourOptions = Array.from({ length: 24 }, (unused, hour) => ({
    value: String(hour),
    label: new Date(SUNDAY + hour * 3600000).toLocaleTimeString(undefined, {
      hour: 'numeric',
      minute: '2-digit',
      timeZone: 'UTC'
    })
  }));

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      this.view = await getView();
    } catch (error) {
      this.errorMessage = bodyMessage(error);
    }
  }

  get needsPermission() {
    return Boolean(this.view && !this.view.canUseConnection);
  }

  get needsConnection() {
    return Boolean(this.view && this.view.canUseConnection && !this.view.connected);
  }

  get hasReports() {
    return Boolean(this.view && this.view.reports.length);
  }

  get isWeekly() {
    return this.form.frequency === 'weekly';
  }

  get isMonthly() {
    return this.form.frequency === 'monthly';
  }

  get hourValue() {
    return String(this.form.hour);
  }

  get rows() {
    return ((this.view && this.view.reports) || []).map((report) => {
      const result = this.results[report.id];
      return {
        ...report,
        url: `/lightning/r/Report/${report.id}/view`,
        detail: [report.folder, report.description].filter(Boolean).join(' · '),
        canSubscribe: Boolean(this.view.canSubscribe) && this.editingId !== report.id,
        editing: this.editingId === report.id,
        saving: this.savingId === report.id,
        subscribeDisabled: Boolean(this.savingId),
        resultMessage: result && result.message,
        resultVariant: result && result.variant
      };
    });
  }

  handleEdit(event) {
    this.editingId = event.target.dataset.id;
  }

  handleCancel() {
    this.editingId = undefined;
  }

  handleField(event) {
    const name = event.target.dataset.field;
    const raw = event.detail.value;
    const value = name === 'hour' || name === 'monthDay' ? Number(raw) : raw;
    this.form = { ...this.form, [name]: value };
  }

  async handleSave() {
    const reportId = this.editingId;
    const report = this.view.reports.find((each) => each.id === reportId);
    this.editingId = undefined;
    this.savingId = reportId;
    try {
      const jobId = await subscribe({
        scheduleJson: JSON.stringify({ reportId, ...this.form })
      });
      const outcome = await this.poll(jobId, 0, false);
      this.setResult(
        reportId,
        outcome.state === 'Subscribed'
          ? {
              variant: 'success',
              message: helpText('Core', 'Core_ReportSubscriptions_Subscribed', report.name)
            }
          : {
              variant: 'error',
              message: outcome.message || helpText('Core', 'Core_ReportSubscriptions_JobFailed')
            }
      );
    } catch (error) {
      this.setResult(reportId, { variant: 'error', message: bodyMessage(error) });
    } finally {
      this.savingId = undefined;
    }
  }

  setResult(reportId, result) {
    this.results = { ...this.results, [reportId]: result };
  }

  /** Until the job is done; a finished job is read once more, so a late failure entry is seen. */
  async poll(jobId, attempt, finishedOnce) {
    const outcome = await check({ jobId });
    if (outcome.state === 'Failed' || (outcome.state === 'Subscribed' && finishedOnce)) {
      return outcome;
    }
    if (attempt >= MAX_POLLS) {
      return {
        state: 'Failed',
        message: helpText('Core', 'Core_ReportSubscriptions_StillWaiting')
      };
    }
    await new Promise((resolve) => {
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      setTimeout(resolve, POLL_MS);
    });
    return this.poll(jobId, attempt + 1, outcome.state === 'Subscribed');
  }
}
