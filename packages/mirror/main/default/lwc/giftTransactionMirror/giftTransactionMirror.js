import { LightningElement } from 'lwc';
import LOCALE from '@salesforce/i18n/locale';
import CURRENCY from '@salesforce/i18n/currency';
import TIME_ZONE from '@salesforce/i18n/timeZone';
import getStatus from '@salesforce/apex/GiftTransactionMirrorController.getStatus';
import runNow from '@salesforce/apex/GiftTransactionMirrorController.runNow';
import schedule from '@salesforce/apex/GiftTransactionMirrorController.schedule';
import stop from '@salesforce/apex/GiftTransactionMirrorController.stop';
import compare from '@salesforce/apex/GiftTransactionMirrorController.compare';
import copyRangeAgain from '@salesforce/apex/GiftTransactionMirrorController.copyRangeAgain';
import title from '@salesforce/label/c.Mirror_GiftTransactionMirror_Title';
import unavailable from '@salesforce/label/c.Mirror_GiftTransactionMirror_Unavailable';
import switchedOff from '@salesforce/label/c.Mirror_GiftTransactionMirror_SwitchedOff';
import directionGifts from '@salesforce/label/c.Mirror_GiftTransactionMirror_DirectionGifts';
import noAccess from '@salesforce/label/c.Mirror_GiftTransactionMirror_NoAccess';
import runNowLabel from '@salesforce/label/c.Core_HealthCheck_RunNowButton';
import scheduleNightly from '@salesforce/label/c.Giving_NightlyJobs_ScheduleButton';
import stopSchedule from '@salesforce/label/c.Giving_NightlyJobs_StopButton';
import copyAgain from '@salesforce/label/c.Mirror_OpportunityMirror_CopyAgain';
import giftTransactionSide from '@salesforce/label/c.Mirror_GiftTransactionMirror_GiftTransactionSide';
import columnGiftTransaction from '@salesforce/label/c.Mirror_GiftTransactionMirror_ColumnGiftTransaction';
import columnGiftTransactionAmount from '@salesforce/label/c.Mirror_GiftTransactionMirror_ColumnGiftTransactionAmount';
import columnTransactionDate from '@salesforce/label/c.Mirror_GiftTransactionMirror_ColumnTransactionDate';
// Wording both mirror pages share, kept once to stay within the org's custom label limit.
import noManagePermission from '@salesforce/label/c.Mirror_OpportunityMirror_NoManagePermission';
import nextRun from '@salesforce/label/c.Mirror_OpportunityMirror_NextRun';
import notScheduled from '@salesforce/label/c.Mirror_OpportunityMirror_NotScheduled';
import runningNow from '@salesforce/label/c.Mirror_OpportunityMirror_Running';
import started from '@salesforce/label/c.Mirror_OpportunityMirror_Started';
import lastRun from '@salesforce/label/c.Mirror_OpportunityMirror_LastRun';
import noLastRun from '@salesforce/label/c.Mirror_OpportunityMirror_NoLastRun';
import loading from '@salesforce/label/c.Core_AccessExplorer_Loading';
import reconciliationTitle from '@salesforce/label/c.Mirror_OpportunityMirror_ReconciliationTitle';
import fromDate from '@salesforce/label/c.Mirror_OpportunityMirror_FromDate';
import toDate from '@salesforce/label/c.Mirror_OpportunityMirror_ToDate';
import compareLabel from '@salesforce/label/c.Core_RollupBuilder_DlrsImportCompare';
import giftSide from '@salesforce/label/c.Mirror_OpportunityMirror_GiftSide';
import noDifferences from '@salesforce/label/c.Core_AccessCompare_NoDifferences';
import differenceCount from '@salesforce/label/c.Mirror_OpportunityMirror_DifferenceCount';
import differenceCountAll from '@salesforce/label/c.Mirror_OpportunityMirror_DifferenceCountAll';
import columnGift from '@salesforce/label/c.Giving_Section_Gift';
import columnGiftAmount from '@salesforce/label/c.Mirror_OpportunityMirror_ColumnGiftAmount';
import columnGiftDate from '@salesforce/label/c.Giving_AskPipeline_FieldGiftDate';
import columnDifference from '@salesforce/label/c.Core_AccessCompare_ColDifference';
import errorFailed from '@salesforce/label/c.Mirror_OpportunityMirror_ErrorFailed';
import { differenceTextOf, fill, isoDate, rowsOf, viewOf } from './mirrorView';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

/** How often the page asks whether a run it shows as running has finished. */
const POLL_MS = 10000;

/**
 * The Gift Transaction mirror page (feature X-07). The controller decides what the org and the
 * person allow and refuses in words; the page shows the direction, the run and schedule buttons,
 * and the reconciliation of a date range. What shows is worked out in `mirrorView`.
 */
export default class GiftTransactionMirror extends LightningElement {
  helpReady = isHelpLoaded('Mirror');

  /** What this page needs from Setup, shown by Core's settingsSetupNotes. */
  setupNotes = [
    {
      key: 'fundraisingUser',
      get what() {
        return helpText('Mirror', 'Mirror_SetupNote_GiftTransactionMirror_What');
      },
      get why() {
        return helpText('Mirror', 'Mirror_SetupNote_GiftTransactionMirror_Why');
      },
      get steps() {
        return helpText('Mirror', 'Mirror_SetupNote_GiftTransactionMirror_Steps');
      },
      link: 'permissionSets'
    }
  ];

  labels = {
    loading,
    title,
    get intro() {
      return helpText('Mirror', 'Mirror_GiftTransactionMirror_Intro');
    },
    unavailable,
    switchedOff,
    noManagePermission,
    noAccess,
    runNow: runNowLabel,
    scheduleNightly,
    stopSchedule,
    reconciliationTitle,
    get reconciliationIntro() {
      return helpText('Mirror', 'Mirror_GiftTransactionMirror_ReconciliationIntro');
    },
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
      label: columnGiftTransaction,
      fieldName: 'giftTransactionUrl',
      type: 'url',
      typeAttributes: { label: { fieldName: 'giftTransactionLabel' } }
    },
    {
      label: columnGiftTransactionAmount,
      fieldName: 'giftTransactionAmount',
      type: 'currency',
      typeAttributes: { currencyCode: CURRENCY }
    },
    { label: columnTransactionDate, fieldName: 'transactionDate', type: 'date-local' },
    { label: columnDifference, fieldName: 'reason', wrapText: true }
  ];

  status;
  comparison;
  working = false;
  justStarted = false;
  error;
  fromDate = isoDate(new Date(new Date().getFullYear(), 0, 1));
  toDate = isoDate(new Date());
  /** The range last compared, which Copy These Gifts Again copies whatever the fields say now. */
  compared;
  pollTimer;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Mirror').then(() => {
        this.helpReady = true;
      });
    }
    this.refresh();
  }

  disconnectedCallback() {
    clearTimeout(this.pollTimer);
  }

  async refresh() {
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

  get view() {
    return viewOf(this.status, this.working);
  }

  get spinnerShown() {
    return this.working || (!this.view.loaded && !this.error);
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

  get directionText() {
    return fill(
      directionGifts,
      this.status.startDate ? this.day(this.status.startDate) : '',
      this.status.paidStatus
    );
  }

  get scheduleText() {
    return this.view.scheduled ? fill(nextRun, this.moment(this.status.nextRunAt)) : notScheduled;
  }

  get lastRunText() {
    return this.status.lastRunAt
      ? fill(lastRun, this.moment(this.status.lastRunAt), this.status.lastSummary || '')
      : noLastRun;
  }

  get runningText() {
    return this.justStarted ? started : runningNow;
  }

  get copyAgainShown() {
    return this.view.onShown && this.hasDifferences;
  }

  get hasDifferences() {
    return Boolean(this.comparison && this.comparison.differenceCount > 0);
  }

  get giftSideText() {
    return fill(giftSide, this.comparison.giftCount, this.money(this.comparison.giftTotal));
  }

  get giftTransactionSideText() {
    return fill(
      giftTransactionSide,
      this.comparison.giftTransactionCount,
      this.money(this.comparison.giftTransactionTotal)
    );
  }

  get differenceText() {
    return differenceTextOf(this.comparison, {
      noDifferences,
      differenceCount,
      differenceCountAll
    });
  }

  get rows() {
    return rowsOf(this.comparison);
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
