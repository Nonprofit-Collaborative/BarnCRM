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
import { localIsoDate } from 'c/findCsv';
import title from '@salesforce/label/c.Mirror_OpportunityMirror_Title';
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
import columnDifference from '@salesforce/label/c.Core_AccessCompare_ColDifference';
import loading from '@salesforce/label/c.Core_AccessExplorer_Loading';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { iconFor } from 'c/barnIcons';

const GIFTS_TO_OPPORTUNITIES = 'GiftsToOpportunities';
const OFF = 'Off';
/** How often the page asks whether a run it shows as running has finished. */
const POLL_MS = 10000;

function fill(template, ...values) {
  return values.reduce((text, value, index) => text.replace(`{${index}}`, value), template);
}

const isoDate = localIsoDate;

/**
 * The Opportunity mirror page (feature X-01). The controller decides what the org and the person
 * allow and refuses in words; the page shows the direction, the run and schedule buttons, and
 * the reconciliation of a date range.
 */
export default class OpportunityMirror extends LightningElement {
  helpReady = isHelpLoaded('Mirror');

  /** What this page needs from Setup, shown by Core's settingsSetupNotes. */
  setupNotes = [
    {
      key: 'opportunityAccess',
      get what() {
        return helpText('Mirror', 'Mirror_SetupNote_Mirror_What');
      },
      get why() {
        return helpText('Mirror', 'Mirror_SetupNote_Mirror_Why');
      },
      get steps() {
        return helpText('Mirror', 'Mirror_SetupNote_Mirror_Steps');
      },
      link: 'permissionSets'
    }
  ];

  labels = {
    loading,
    title,
    get intro() {
      return helpText('Mirror', 'Mirror_OpportunityMirror_Intro');
    },
    get unavailable() {
      return helpText('Mirror', 'Mirror_OpportunityMirror_Unavailable');
    },
    get switchedOff() {
      return helpText('Mirror', 'Mirror_OpportunityMirror_SwitchedOff');
    },
    get noManagePermission() {
      return helpText('Mirror', 'Mirror_OpportunityMirror_NoManagePermission');
    },
    get noOpportunityAccess() {
      return helpText('Mirror', 'Mirror_OpportunityMirror_NoOpportunityAccess');
    },
    runNow: runNowLabel,
    scheduleNightly,
    stopSchedule,
    reconciliationTitle,
    get reconciliationIntro() {
      return helpText('Mirror', 'Mirror_OpportunityMirror_ReconciliationIntro');
    },
    fromDate,
    toDate,
    compare: compareLabel,
    copyAgain,
    columnGift,
    columnGiftAmount,
    columnOpportunity,
    columnOpportunityAmount
  };

  icons = { opportunityMirror: iconFor('Opportunity_Mirror') };

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
    if (!this.helpReady) {
      loadHelp('Mirror').then(() => {
        this.helpReady = true;
      });
    }
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
      return helpText('Mirror', 'Mirror_OpportunityMirror_DirectionGifts');
    }
    return this.status.startDate
      ? fill(
          helpText('Mirror', 'Mirror_OpportunityMirror_DirectionOpportunities'),
          this.day(this.status.startDate)
        )
      : helpText('Mirror', 'Mirror_OpportunityMirror_NoStartDate');
  }

  get scheduled() {
    return Boolean(this.status && this.status.nextRunAt);
  }

  get scheduleText() {
    return this.scheduled
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
    return this.justStarted
      ? helpText('Mirror', 'Mirror_OpportunityMirror_Started')
      : helpText('Mirror', 'Mirror_OpportunityMirror_Running');
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

  get currencyCode() {
    return CURRENCY;
  }

  /** No differences is good news; any difference is a warning. */
  get differenceVariant() {
    return this.hasDifferences ? 'warning' : 'success';
  }

  get differenceText() {
    if (!this.hasDifferences) {
      return noDifferences;
    }
    const { differenceCount: count, differences } = this.comparison;
    return count > differences.length
      ? fill(
          helpText('Mirror', 'Mirror_OpportunityMirror_DifferenceCount'),
          count,
          differences.length
        )
      : fill(helpText('Mirror', 'Mirror_OpportunityMirror_DifferenceCountAll'), count);
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
    return (
      (failure && failure.body && failure.body.message) ||
      helpText('Mirror', 'Mirror_OpportunityMirror_ErrorFailed')
    );
  }
}
