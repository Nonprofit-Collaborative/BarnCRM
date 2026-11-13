import { LightningElement, api } from 'lwc';
import LOCALE from '@salesforce/i18n/locale';
import CURRENCY from '@salesforce/i18n/currency';
import TIME_ZONE from '@salesforce/i18n/timeZone';
import getOpportunityStatus from '@salesforce/apex/OpportunityMirrorController.getStatus';
import runOpportunityMirror from '@salesforce/apex/OpportunityMirrorController.runNow';
import scheduleOpportunityMirror from '@salesforce/apex/OpportunityMirrorController.schedule';
import stopOpportunityMirror from '@salesforce/apex/OpportunityMirrorController.stop';
import compareOpportunities from '@salesforce/apex/OpportunityMirrorController.compare';
import copyOpportunitiesAgain from '@salesforce/apex/OpportunityMirrorController.copyRangeAgain';
import getGiftTransactionStatus from '@salesforce/apex/GiftTransactionMirrorController.getStatus';
import runGiftTransactionMirror from '@salesforce/apex/GiftTransactionMirrorController.runNow';
import scheduleGiftTransactionMirror from '@salesforce/apex/GiftTransactionMirrorController.schedule';
import stopGiftTransactionMirror from '@salesforce/apex/GiftTransactionMirrorController.stop';
import compareGiftTransactions from '@salesforce/apex/GiftTransactionMirrorController.compare';
import copyGiftTransactionsAgain from '@salesforce/apex/GiftTransactionMirrorController.copyRangeAgain';
import opportunityTitle from '@salesforce/label/c.Mirror_OpportunityMirror_Title';
import giftTransactionTitle from '@salesforce/label/c.Mirror_GiftTransactionMirror_Title';
import runNowLabel from '@salesforce/label/c.Core_HealthCheck_RunNowButton';
import scheduleNightly from '@salesforce/label/c.Giving_NightlyJobs_ScheduleButton';
import stopSchedule from '@salesforce/label/c.Giving_NightlyJobs_StopButton';
import nextRun from '@salesforce/label/c.Mirror_OpportunityMirror_NextRun';
import reconciliationTitle from '@salesforce/label/c.Mirror_OpportunityMirror_ReconciliationTitle';
import fromDate from '@salesforce/label/c.Mirror_OpportunityMirror_FromDate';
import toDate from '@salesforce/label/c.Mirror_OpportunityMirror_ToDate';
import compareLabel from '@salesforce/label/c.Mirror_Sync_Compare';
import copyAgain from '@salesforce/label/c.Mirror_OpportunityMirror_CopyAgain';
import noDifferences from '@salesforce/label/c.Core_AccessCompare_NoDifferences';
import columnGift from '@salesforce/label/c.Giving_Section_Gift';
import columnGiftAmount from '@salesforce/label/c.Mirror_OpportunityMirror_ColumnGiftAmount';
import columnGiftDate from '@salesforce/label/c.Giving_AskPipeline_FieldGiftDate';
import columnOpportunity from '@salesforce/label/c.Mirror_OpportunityMirror_ColumnOpportunity';
import columnOpportunityAmount from '@salesforce/label/c.Mirror_OpportunityMirror_ColumnOpportunityAmount';
import columnCloseDate from '@salesforce/label/c.Mirror_OpportunityMirror_ColumnCloseDate';
import columnGiftTransaction from '@salesforce/label/c.Mirror_GiftTransactionMirror_ColumnGiftTransaction';
import columnGiftTransactionAmount from '@salesforce/label/c.Mirror_GiftTransactionMirror_ColumnGiftTransactionAmount';
import columnTransactionDate from '@salesforce/label/c.Mirror_GiftTransactionMirror_ColumnTransactionDate';
import columnDifference from '@salesforce/label/c.Core_AccessCompare_ColDifference';
import loading from '@salesforce/label/c.Core_AccessExplorer_Loading';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { iconFor } from 'c/barnIcons';
import { differenceTextOf, fill, isoDate, rowsOf, viewOf } from './mirrorView';

/** How often the page asks whether a run it shows as running has finished. */
const POLL_MS = 10000;
const GIFTS_TO_OPPORTUNITIES = 'GiftsToOpportunities';

/**
 * What differs between the two gift mirrors' pages (D-200 S5): the controller, the wording, the
 * mirrored record's columns and how the direction reads. Help keys stay literal for the checks.
 */
const KINDS = {
  opportunity: {
    calls: {
      getStatus: getOpportunityStatus,
      runNow: runOpportunityMirror,
      schedule: scheduleOpportunityMirror,
      stop: stopOpportunityMirror,
      compare: compareOpportunities,
      copyRangeAgain: copyOpportunitiesAgain
    },
    title: opportunityTitle,
    icon: 'Opportunity_Mirror',
    linked: 'opportunity',
    columnLinked: columnOpportunity,
    columnLinkedAmount: columnOpportunityAmount,
    columnLinkedDate: columnCloseDate,
    linkedDate: 'closeDate',
    texts: () => ({
      intro: helpText('Mirror', 'Mirror_OpportunityMirror_Intro'),
      unavailable: helpText('Mirror', 'Mirror_OpportunityMirror_Unavailable'),
      switchedOff: helpText('Mirror', 'Mirror_OpportunityMirror_SwitchedOff'),
      noAccess: helpText('Mirror', 'Mirror_OpportunityMirror_NoOpportunityAccess'),
      reconciliationIntro: helpText('Mirror', 'Mirror_OpportunityMirror_ReconciliationIntro')
    }),
    setupNote: () => ({
      key: 'opportunityAccess',
      what: helpText('Mirror', 'Mirror_SetupNote_Mirror_What'),
      why: helpText('Mirror', 'Mirror_SetupNote_Mirror_Why'),
      steps: helpText('Mirror', 'Mirror_SetupNote_Mirror_Steps'),
      link: 'permissionSets'
    }),
    directionText(status, day) {
      if (status.direction === GIFTS_TO_OPPORTUNITIES) {
        return helpText('Mirror', 'Mirror_OpportunityMirror_DirectionGifts');
      }
      return status.startDate
        ? fill(
            helpText('Mirror', 'Mirror_OpportunityMirror_DirectionOpportunities'),
            day(status.startDate)
          )
        : helpText('Mirror', 'Mirror_OpportunityMirror_NoStartDate');
    },
    /** Copy again copies gifts, so only Gifts to Opportunities offers it. */
    copiesAgain: (status) => status.direction === GIFTS_TO_OPPORTUNITIES
  },
  giftTransaction: {
    calls: {
      getStatus: getGiftTransactionStatus,
      runNow: runGiftTransactionMirror,
      schedule: scheduleGiftTransactionMirror,
      stop: stopGiftTransactionMirror,
      compare: compareGiftTransactions,
      copyRangeAgain: copyGiftTransactionsAgain
    },
    title: giftTransactionTitle,
    icon: 'Gift_Transaction_Mirror',
    linked: 'giftTransaction',
    columnLinked: columnGiftTransaction,
    columnLinkedAmount: columnGiftTransactionAmount,
    columnLinkedDate: columnTransactionDate,
    linkedDate: 'transactionDate',
    texts: () => ({
      intro: helpText('Mirror', 'Mirror_GiftTransactionMirror_Intro'),
      unavailable: helpText('Mirror', 'Mirror_GiftTransactionMirror_Unavailable'),
      switchedOff: helpText('Mirror', 'Mirror_GiftTransactionMirror_SwitchedOff'),
      noAccess: helpText('Mirror', 'Mirror_GiftTransactionMirror_NoAccess'),
      reconciliationIntro: helpText('Mirror', 'Mirror_GiftTransactionMirror_ReconciliationIntro')
    }),
    setupNote: () => ({
      key: 'fundraisingUser',
      what: helpText('Mirror', 'Mirror_SetupNote_GiftTransactionMirror_What'),
      why: helpText('Mirror', 'Mirror_SetupNote_GiftTransactionMirror_Why'),
      steps: helpText('Mirror', 'Mirror_SetupNote_GiftTransactionMirror_Steps'),
      link: 'permissionSets'
    }),
    directionText(status, day) {
      return fill(
        helpText('Mirror', 'Mirror_GiftTransactionMirror_DirectionGifts'),
        status.startDate ? day(status.startDate) : '',
        status.paidStatus
      );
    },
    copiesAgain: () => true
  }
};

/**
 * One gift mirror's page (features X-01 and X-07), shared by `c/opportunityMirror` and
 * `c/giftTransactionMirror`, which name their `kind`. The controller decides what the org and the
 * person allow and refuses in words; the page shows the direction, the run and schedule buttons,
 * and the reconciliation of a date range. What shows is worked out in `mirrorView`.
 */
export default class MirrorPage extends LightningElement {
  /** `opportunity` or `giftTransaction`. */
  @api kind;

  helpReady = isHelpLoaded('Mirror');
  status;
  comparison;
  working = false;
  justStarted = false;
  error;
  fromDate = isoDate(new Date(new Date().getFullYear(), 0, 1));
  toDate = isoDate(new Date());
  /** The range last compared, which Copy Again copies whatever the date fields say now. */
  compared;
  pollTimer;

  get mirror() {
    return KINDS[this.kind] || KINDS.opportunity;
  }

  get calls() {
    return this.mirror.calls;
  }

  /** What this page needs from Setup, shown by Core's settingsSetupNotes. */
  get setupNotes() {
    return [this.mirror.setupNote()];
  }

  get labels() {
    const mirror = this.mirror;
    return {
      ...mirror.texts(),
      loading,
      title: mirror.title,
      noManagePermission: helpText('Mirror', 'Mirror_OpportunityMirror_NoManagePermission'),
      runNow: runNowLabel,
      scheduleNightly,
      stopSchedule,
      reconciliationTitle,
      fromDate,
      toDate,
      compare: compareLabel,
      copyAgain,
      columnGift,
      columnGiftAmount,
      columnLinked: mirror.columnLinked,
      columnLinkedAmount: mirror.columnLinkedAmount
    };
  }

  get iconName() {
    return iconFor(this.mirror.icon);
  }

  get columns() {
    const { linked, columnLinked, columnLinkedAmount, columnLinkedDate, linkedDate } = this.mirror;
    return [
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
        label: columnLinked,
        fieldName: `${linked}Url`,
        type: 'url',
        typeAttributes: { label: { fieldName: `${linked}Label` } }
      },
      {
        label: columnLinkedAmount,
        fieldName: `${linked}Amount`,
        type: 'currency',
        typeAttributes: { currencyCode: CURRENCY }
      },
      { label: columnLinkedDate, fieldName: linkedDate, type: 'date-local' },
      { label: columnDifference, fieldName: 'reason', wrapText: true }
    ];
  }

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
      this.show(await this.calls.getStatus());
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
    return this.mirror.directionText(this.status, (value) => this.day(value));
  }

  get scheduleText() {
    return this.view.scheduled
      ? fill(nextRun, this.moment(this.status.nextRunAt))
      : helpText('Mirror', 'Mirror_OpportunityMirror_NotScheduled');
  }

  get lastRunText() {
    return this.status.lastRunAt
      ? fill(
          helpText('Mirror', 'Mirror_OpportunityMirror_LastRun'),
          this.moment(this.status.lastRunAt),
          this.status.lastSummary || ''
        )
      : helpText('Mirror', 'Mirror_OpportunityMirror_NoLastRun');
  }

  get runningText() {
    return this.justStarted
      ? helpText('Mirror', 'Mirror_OpportunityMirror_Started')
      : helpText('Mirror', 'Mirror_OpportunityMirror_Running');
  }

  get copyAgainShown() {
    return this.view.onShown && this.mirror.copiesAgain(this.status) && this.hasDifferences;
  }

  get hasDifferences() {
    return Boolean(this.comparison && this.comparison.differenceCount > 0);
  }

  get currencyCode() {
    return CURRENCY;
  }

  /** The mirrored side's count and total in the comparison. */
  get linkedCount() {
    return this.comparison[`${this.mirror.linked}Count`];
  }

  get linkedTotal() {
    return this.comparison[`${this.mirror.linked}Total`];
  }

  /** No differences is good news; any difference is a warning. */
  get differenceVariant() {
    return this.hasDifferences ? 'warning' : 'success';
  }

  get differenceText() {
    return differenceTextOf(this.comparison, {
      noDifferences,
      differenceCount: helpText('Mirror', 'Mirror_OpportunityMirror_DifferenceCount'),
      differenceCountAll: helpText('Mirror', 'Mirror_OpportunityMirror_DifferenceCountAll')
    });
  }

  get rows() {
    return rowsOf(this.comparison, this.mirror.linked);
  }

  handleFrom(event) {
    this.fromDate = event.target.value;
  }

  handleTo(event) {
    this.toDate = event.target.value;
  }

  handleRunNow() {
    this.act(() => this.calls.runNow(), true);
  }

  handleSchedule() {
    this.act(() => this.calls.schedule(), false);
  }

  handleStop() {
    this.act(() => this.calls.stop(), false);
  }

  handleCopyAgain() {
    this.act(() => this.calls.copyRangeAgain({ ...this.compared }), true);
  }

  async handleCompare() {
    this.error = undefined;
    this.working = true;
    const range = { fromDate: this.fromDate, toDate: this.toDate };
    try {
      this.comparison = await this.calls.compare(range);
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
    return (
      (failure && failure.body && failure.body.message) ||
      helpText('Mirror', 'Mirror_OpportunityMirror_ErrorFailed')
    );
  }
}
