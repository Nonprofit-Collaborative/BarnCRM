import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPage from '@salesforce/apex/RecurringHealthController.getPage';
import createFollowUp from '@salesforce/apex/RecurringHealthController.createFollowUp';
import { messageFrom } from 'c/findCsv';
import { iconFor } from 'c/barnIcons';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import {
  REASON_CANCELLED,
  REASON_CARD,
  REASON_FAILED,
  REASON_OVERDUE,
  atRisk,
  lastTwelveMonths,
  recurringRevenue
} from 'c/recurringHealthModel';

const HELP = 'Giving';

const recordHref = (recordId) => `/lightning/r/${recordId}/view`;

const number = new Intl.NumberFormat(undefined, {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2
});

function dateText(iso) {
  if (!iso) {
    return '';
  }
  const [year, month, day] = String(iso).split('-').map(Number);
  return new Date(year, month - 1, day).toLocaleDateString();
}

/** One reason in words, with its date or count. */
function reasonText(reason, row) {
  switch (reason) {
    case REASON_FAILED:
      return helpText(
        'Giving',
        'Giving_RecurringHealth_ReasonFailed',
        row.failedCharges,
        dateText(row.lastFailedCharge)
      );
    case REASON_CARD:
      return helpText('Giving', 'Giving_RecurringHealth_ReasonCard', dateText(row.cardExpires));
    case REASON_CANCELLED:
      return helpText(
        'Giving',
        'Giving_RecurringHealth_ReasonCancelled',
        dateText(row.cancelledAtProcessor)
      );
    case REASON_OVERDUE:
      return helpText('Giving', 'Giving_RecurringHealth_ReasonOverdue', dateText(row.overdueSince));
    default:
      return '';
  }
}

/**
 * The Recurring Donor Health page (G-27, canonical model R-RH3, R-RH4): monthly recurring
 * revenue, active recurring gifts and the revenue at risk; twelve months of recurring gifts
 * received; the count of unmatched processor events; and the Save the Sustainer list with Create
 * Follow-Up Task. Figures come from `RecurringHealthController.getPage` and are worked out in
 * `c/recurringHealthModel`.
 */
export default class RecurringDonorHealth extends LightningElement {
  helpReady = isHelpLoaded(HELP);
  icon = iconFor('Recurring_Donor_Health');
  page;
  isLoading = true;
  isWorking = false;
  errorMessage;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(HELP).then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  get labels() {
    return {
      title: helpText('Giving', 'Giving_RecurringHealth_Title'),
      intro: helpText('Giving', 'Giving_RecurringHealth_Intro'),
      mrr: helpText('Giving', 'Giving_RecurringHealth_Mrr'),
      active: helpText('Giving', 'Giving_RecurringHealth_Active'),
      atRisk: helpText('Giving', 'Giving_RecurringHealth_AtRisk'),
      months: helpText('Giving', 'Giving_RecurringHealth_Months'),
      list: helpText('Giving', 'Giving_RecurringHealth_List'),
      noRows: helpText('Giving', 'Giving_RecurringHealth_NoRows'),
      followUp: helpText('Giving', 'Giving_RecurringHealth_FollowUp')
    };
  }

  async load() {
    this.isLoading = true;
    try {
      this.page = await getPage();
      this.errorMessage = undefined;
    } catch (error) {
      this.page = undefined;
      this.errorMessage = messageFrom(
        error,
        helpText('Giving', 'Giving_RecurringHealth_Unexpected')
      );
    } finally {
      this.isLoading = false;
    }
  }

  get revenue() {
    return recurringRevenue(this.page && this.page.byFrequency);
  }

  get risk() {
    const result = atRisk(this.page && this.page.rows);
    return {
      total: result.total,
      rows: result.rows.map((row) => ({
        ...row,
        href: recordHref(row.id),
        title: row.donorName ? `${row.donorName} (${row.name})` : row.name,
        amountText: helpText(
          'Giving',
          'Giving_RecurringHealth_Amount',
          number.format(row.amount || 0),
          row.frequency || '',
          number.format(row.monthly)
        ),
        reasonText: row.reasons.map((reason) => reasonText(reason, row)).join(' ')
      }))
    };
  }

  get hasRows() {
    return this.risk.rows.length > 0;
  }

  get months() {
    return lastTwelveMonths(this.page && this.page.months).map((row) => ({
      ...row,
      label: new Date(row.year, row.month - 1, 1).toLocaleDateString(undefined, {
        month: 'short',
        year: 'numeric'
      })
    }));
  }

  get hasUnmatched() {
    return Boolean(this.page && this.page.unmatched > 0);
  }

  get unmatchedMessage() {
    return helpText(
      'Giving',
      'Giving_RecurringHealth_Unmatched',
      this.page ? this.page.unmatched : 0
    );
  }

  async handleFollowUp(event) {
    this.isWorking = true;
    try {
      await createFollowUp({ commitmentId: event.currentTarget.dataset.rowId });
      this.dispatchEvent(
        new ShowToastEvent({
          message: helpText('Giving', 'Giving_RecurringHealth_TaskCreated'),
          variant: 'success'
        })
      );
    } catch (error) {
      this.errorMessage = messageFrom(
        error,
        helpText('Giving', 'Giving_RecurringHealth_Unexpected')
      );
    } finally {
      this.isWorking = false;
    }
  }
}
