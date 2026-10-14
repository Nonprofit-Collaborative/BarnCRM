import { LightningElement } from 'lwc';
import LOCALE from '@salesforce/i18n/locale';
import CURRENCY from '@salesforce/i18n/currency';
import TIME_ZONE from '@salesforce/i18n/timeZone';
import getStatus from '@salesforce/apex/OpportunityMirrorController.getStatus';
import runNow from '@salesforce/apex/OpportunityMirrorController.runNow';
import schedule from '@salesforce/apex/OpportunityMirrorController.schedule';
import stop from '@salesforce/apex/OpportunityMirrorController.stop';
import compare from '@salesforce/apex/OpportunityMirrorController.compare';
import copyRangeAgain from '@salesforce/apex/OpportunityMirrorController.copyRangeAgain';
import title from '@salesforce/label/c.Connect_OpportunityMirror_Title';
import intro from '@salesforce/label/c.Connect_OpportunityMirror_Intro';
import unavailable from '@salesforce/label/c.Connect_OpportunityMirror_Unavailable';
import switchedOff from '@salesforce/label/c.Connect_OpportunityMirror_SwitchedOff';
import directionGifts from '@salesforce/label/c.Connect_OpportunityMirror_DirectionGifts';
import directionOpportunities from '@salesforce/label/c.Connect_OpportunityMirror_DirectionOpportunities';
import noStartDate from '@salesforce/label/c.Connect_OpportunityMirror_NoStartDate';
import noManagePermission from '@salesforce/label/c.Connect_OpportunityMirror_NoManagePermission';
import noOpportunityAccess from '@salesforce/label/c.Connect_OpportunityMirror_NoOpportunityAccess';
import runNowLabel from '@salesforce/label/c.Connect_OpportunityMirror_RunNow';
import scheduleNightly from '@salesforce/label/c.Connect_OpportunityMirror_ScheduleNightly';
import stopSchedule from '@salesforce/label/c.Connect_OpportunityMirror_StopSchedule';
import nextRun from '@salesforce/label/c.Connect_OpportunityMirror_NextRun';
import notScheduled from '@salesforce/label/c.Connect_OpportunityMirror_NotScheduled';
import running from '@salesforce/label/c.Connect_OpportunityMirror_Running';
import started from '@salesforce/label/c.Connect_OpportunityMirror_Started';
import reconciliationTitle from '@salesforce/label/c.Connect_OpportunityMirror_ReconciliationTitle';
import reconciliationIntro from '@salesforce/label/c.Connect_OpportunityMirror_ReconciliationIntro';
import fromDate from '@salesforce/label/c.Connect_OpportunityMirror_FromDate';
import toDate from '@salesforce/label/c.Connect_OpportunityMirror_ToDate';
import compareLabel from '@salesforce/label/c.Connect_OpportunityMirror_Compare';
import copyAgain from '@salesforce/label/c.Connect_OpportunityMirror_CopyAgain';
import giftSide from '@salesforce/label/c.Connect_OpportunityMirror_GiftSide';
import opportunitySide from '@salesforce/label/c.Connect_OpportunityMirror_OpportunitySide';
import noDifferences from '@salesforce/label/c.Connect_OpportunityMirror_NoDifferences';
import differenceCount from '@salesforce/label/c.Connect_OpportunityMirror_DifferenceCount';
import columnGift from '@salesforce/label/c.Connect_OpportunityMirror_ColumnGift';
import columnGiftAmount from '@salesforce/label/c.Connect_OpportunityMirror_ColumnGiftAmount';
import columnGiftDate from '@salesforce/label/c.Connect_OpportunityMirror_ColumnGiftDate';
import columnOpportunity from '@salesforce/label/c.Connect_OpportunityMirror_ColumnOpportunity';
import columnOpportunityAmount from '@salesforce/label/c.Connect_OpportunityMirror_ColumnOpportunityAmount';
import columnCloseDate from '@salesforce/label/c.Connect_OpportunityMirror_ColumnCloseDate';
import columnDifference from '@salesforce/label/c.Connect_OpportunityMirror_ColumnDifference';
import errorFailed from '@salesforce/label/c.Connect_OpportunityMirror_ErrorFailed';
import differenceCountAll from '@salesforce/label/c.Connect_OpportunityMirror_DifferenceCountAll';
import lastRun from '@salesforce/label/c.Connect_OpportunityMirror_LastRun';
import noLastRun from '@salesforce/label/c.Connect_OpportunityMirror_NoLastRun';
import loading from '@salesforce/label/c.Connect_OpportunityMirror_Loading';
import noteWhat from '@salesforce/label/c.Connect_SetupNote_Mirror_What';
import noteWhy from '@salesforce/label/c.Connect_SetupNote_Mirror_Why';
import noteWhere from '@salesforce/label/c.Connect_SetupNote_Mirror_Where';

const GIFTS_TO_OPPORTUNITIES = 'GiftsToOpportunities';
const OFF = 'Off';
/** How often the page asks whether a run it shows as running has finished. */
const POLL_MS = 10000;

function fill(template, ...values) {
  return values.reduce((text, value, index) => text.replace(`{${index}}`, value), template);
}

function isoDate(date) {
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${date.getFullYear()}-${month}-${day}`;
}

/**
 * The Opportunity mirror page (feature X-01). The controller decides what the org and the person
 * allow and refuses in words; the page shows the direction, the run and schedule buttons, and
 * the reconciliation of a date range.
 */
export default class OpportunityMirror extends LightningElement {
  /** What this page needs from Setup, shown by Core's settingsSetupNotes. */
  setupNotes = [{ key: 'opportunityAccess', what: noteWhat, why: noteWhy, where: noteWhere }];

  labels = {
    loading,
    title,
    intro,
    unavailable,
    switchedOff,
    noManagePermission,
    noOpportunityAccess,
    runNow: runNowLabel,
    scheduleNightly,
    stopSchedule,
    reconciliationTitle,
    reconciliationIntro,
    fromDate,
    toDate,
    compare: compareLabel,
    copyAgain
  };

  columns = [
    {
      label: columnGift,
      fieldName: 'giftUrl',
      type: 'url',
      typeAttributes: { label: { fieldName: 'giftName' } }
    },
    {
      label: columnGiftAmount,
      fieldName: 'giftAmount',
      type: 'currency',
      typeAttributes: { currencyCode: CURRENCY }
    },
    { label: columnGiftDate, fieldName: 'giftDate', type: 'date-local' },
    {
      label: columnOpportunity,
      fieldName: 'opportunityUrl',
      type: 'url',
      typeAttributes: { label: { fieldName: 'opportunityLabel' } }
    },
    {
      label: columnOpportunityAmount,
      fieldName: 'opportunityAmount',
      type: 'currency',
      typeAttributes: { currencyCode: CURRENCY }
    },
    { label: columnCloseDate, fieldName: 'closeDate', type: 'date-local' },
    { label: columnDifference, fieldName: 'reason', wrapText: true }
  ];

  status;
  comparison;
  working = false;
  justStarted = false;
  error;
  fromDate = isoDate(new Date(new Date().getFullYear(), 0, 1));
  toDate = isoDate(new Date());
  /** The range last compared, which Copy again copies whatever the date fields say now. */
  compared;
  pollTimer;

  connectedCallback() {
    this.load();
  }

  disconnectedCallback() {
    clearTimeout(this.pollTimer);
  }

  async load() {
    this.error = undefined;
    try {
      this.show(await getStatus());
    } catch (failure) {
      this.error = this.messageOf(failure);
    }
  }

  /** Shows a status, and while a run is going asks again until it has finished. */
  show(status) {
    this.status = status;
    clearTimeout(this.pollTimer);
    if (status && status.running) {
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      this.pollTimer = setTimeout(() => this.refresh(), POLL_MS);
    } else {
      this.justStarted = false;
    }
  }

  async refresh() {
    try {
      this.show(await getStatus());
    } catch (failure) {
      this.error = this.messageOf(failure);
    }
  }

  get loaded() {
    return Boolean(this.status);
  }

  get spinnerShown() {
    return this.working || (!this.loaded && !this.error);
  }

  money(amount) {
    return new Intl.NumberFormat(LOCALE, { style: 'currency', currency: CURRENCY }).format(
      amount || 0
    );
  }

  /** A date the server sends as yyyy-mm-dd, in the viewer's locale, on that same day. */
  day(value) {
    return new Intl.DateTimeFormat(LOCALE, { dateStyle: 'medium', timeZone: 'UTC' }).format(
      new Date(`${value}T00:00:00Z`)
    );
  }

  moment(value) {
    return new Intl.DateTimeFormat(LOCALE, {
      dateStyle: 'medium',
      timeStyle: 'short',
      timeZone: TIME_ZONE
    }).format(new Date(value));
  }

  get available() {
    return this.loaded && this.status.available;
  }

  get unavailableShown() {
    return this.loaded && !this.status.available;
  }

  get offShown() {
    return this.available && this.status.direction === OFF;
  }

  get onShown() {
    return this.available && this.status.direction !== OFF;
  }

  get directionText() {
    if (this.status.direction === GIFTS_TO_OPPORTUNITIES) {
      return directionGifts;
    }
    return this.status.startDate
      ? fill(directionOpportunities, this.day(this.status.startDate))
      : noStartDate;
  }

  get scheduled() {
    return Boolean(this.status && this.status.nextRunAt);
  }

  get scheduleText() {
    return this.scheduled ? fill(nextRun, this.moment(this.status.nextRunAt)) : notScheduled;
  }

  get lastRunText() {
    return this.status.lastRunAt
      ? fill(lastRun, this.moment(this.status.lastRunAt), this.status.lastSummary || '')
      : noLastRun;
  }

  get noManageShown() {
    return this.onShown && !this.status.canManage;
  }

  get noAccessShown() {
    return this.onShown && this.status.canManage && !this.status.canRun;
  }

  get runningShown() {
    return this.onShown && this.status.running;
  }

  get runningText() {
    return this.justStarted ? started : running;
  }

  get manageDisabled() {
    return this.working || !this.status.canManage;
  }

  get scheduleDisabled() {
    return this.manageDisabled || !this.status.canRun;
  }

  get runDisabled() {
    return this.scheduleDisabled || !this.onShown || this.status.running;
  }

  get copyAgainShown() {
    return this.onShown && this.status.direction === GIFTS_TO_OPPORTUNITIES && this.hasDifferences;
  }

  get hasDifferences() {
    return Boolean(this.comparison && this.comparison.differenceCount > 0);
  }

  get giftSideText() {
    return fill(giftSide, this.comparison.giftCount, this.money(this.comparison.giftTotal));
  }

  get opportunitySideText() {
    return fill(
      opportunitySide,
      this.comparison.opportunityCount,
      this.money(this.comparison.opportunityTotal)
    );
  }

  get differenceText() {
    if (!this.hasDifferences) {
      return noDifferences;
    }
    const { differenceCount: count, differences } = this.comparison;
    return count > differences.length
      ? fill(differenceCount, count, differences.length)
      : fill(differenceCountAll, count);
  }

  get rows() {
    return this.comparison.differences.map((row) => ({
      ...row,
      giftUrl: row.giftId ? `/${row.giftId}` : undefined,
      opportunityUrl: row.opportunityId ? `/${row.opportunityId}` : undefined,
      opportunityLabel: row.opportunityName || row.opportunityId
    }));
  }

  handleFrom(event) {
    this.fromDate = event.target.value;
  }

  handleTo(event) {
    this.toDate = event.target.value;
  }

  handleRunNow() {
    this.act(() => runNow(), true);
  }

  handleSchedule() {
    this.act(() => schedule(), false);
  }

  handleStop() {
    this.act(() => stop(), false);
  }

  handleCopyAgain() {
    this.act(() => copyRangeAgain({ ...this.compared }), true);
  }

  async handleCompare() {
    this.error = undefined;
    this.working = true;
    const range = { fromDate: this.fromDate, toDate: this.toDate };
    try {
      this.comparison = await compare(range);
      this.compared = range;
    } catch (failure) {
      this.comparison = undefined;
      this.compared = undefined;
      this.error = this.messageOf(failure);
    } finally {
      this.working = false;
    }
  }

  async act(call, starts) {
    this.error = undefined;
    this.working = true;
    try {
      const status = await call();
      this.justStarted = starts;
      this.show(status);
    } catch (failure) {
      this.error = this.messageOf(failure);
    } finally {
      this.working = false;
    }
  }

  messageOf(failure) {
    return (failure && failure.body && failure.body.message) || errorFailed;
  }
}
