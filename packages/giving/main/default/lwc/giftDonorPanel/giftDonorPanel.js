import { LightningElement, api } from 'lwc';
import LOCALE from '@salesforce/i18n/locale';
import CURRENCY from '@salesforce/i18n/currency';
import getPanel from '@salesforce/apex/GiftDonorPanelController.getPanel';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

/** A money amount in the user's locale and currency, or an empty string. */
export function money(value, locale, currency) {
  if (value === null || value === undefined) {
    return '';
  }
  try {
    return new Intl.NumberFormat(locale, { style: 'currency', currency }).format(value);
  } catch {
    return Number(value).toFixed(2);
  }
}

/** A date-only value (yyyy-mm-dd) as a medium date, read in UTC so the day never shifts. */
export function day(value, locale) {
  if (!value) {
    return '';
  }
  try {
    return new Intl.DateTimeFormat(locale, { dateStyle: 'medium', timeZone: 'UTC' }).format(
      new Date(value)
    );
  } catch {
    return value;
  }
}

/** Puts {0}, {1} ... into a help sentence. */
function fill(text, ...args) {
  return args.reduce((out, arg, i) => out.replace(`{${i}}`, arg), text || '');
}

/**
 * The donor panel in Quick Gift Entry (G-33): the chosen donor's household, giving totals, last
 * gifts and open pledges and recurring gifts, so nobody leaves the form to look. Read only; a
 * failure to load leaves a quiet note and never blocks the gift.
 */
export default class GiftDonorPanel extends LightningElement {
  helpReady = isHelpLoaded('Giving');
  panel;
  failed = false;
  _donorId;
  _request = 0;

  @api
  get donorId() {
    return this._donorId;
  }
  set donorId(value) {
    if (value === this._donorId) {
      return;
    }
    this._donorId = value;
    this.load();
  }

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Giving').then(() => {
        this.helpReady = true;
      });
    }
  }

  load() {
    this.panel = undefined;
    this.failed = false;
    const donorId = this._donorId;
    if (!donorId) {
      return;
    }
    const request = ++this._request;
    getPanel({ donorId })
      .then((panel) => {
        if (request === this._request) {
          this.panel = panel || undefined;
        }
      })
      .catch(() => {
        if (request === this._request) {
          this.failed = true;
        }
      });
  }

  get labels() {
    return {
      title: helpText('Giving', 'Giving_DonorPanel_Title'),
      household: helpText('Giving', 'Giving_DonorPanel_Household'),
      totalGiving: helpText('Giving', 'Giving_DonorPanel_TotalGiving'),
      lastGift: helpText('Giving', 'Giving_DonorPanel_LastGift'),
      gifts: helpText('Giving', 'Giving_DonorPanel_Gifts'),
      commitments: helpText('Giving', 'Giving_DonorPanel_Commitments'),
      noGifts: helpText('Giving', 'Giving_DonorPanel_NoGifts'),
      noCommitments: helpText('Giving', 'Giving_DonorPanel_NoCommitments'),
      loadError: helpText('Giving', 'Giving_DonorPanel_LoadError')
    };
  }

  get hasPanel() {
    return !!this.panel;
  }

  get householdUrl() {
    return this.panel && this.panel.householdId ? `/${this.panel.householdId}` : null;
  }

  get totalGiving() {
    return (
      money(this.panel ? this.panel.totalGiving : null, LOCALE, CURRENCY) ||
      money(0, LOCALE, CURRENCY)
    );
  }

  get lastGiftDate() {
    return day(this.panel ? this.panel.lastGiftDate : null, LOCALE) || '';
  }

  get gifts() {
    return ((this.panel && this.panel.gifts) || []).map((gift) => ({
      key: gift.id,
      url: `/${gift.id}`,
      line: [
        day(gift.giftDate, LOCALE),
        money(gift.amount, LOCALE, CURRENCY),
        gift.paymentMethod,
        gift.status
      ]
        .filter((part) => part)
        .join(', ')
    }));
  }

  get hasGifts() {
    return this.gifts.length > 0;
  }

  get commitments() {
    const balanceText = helpText('Giving', 'Giving_DonorPanel_Balance');
    const nextText = helpText('Giving', 'Giving_DonorPanel_NextDue');
    return ((this.panel && this.panel.commitments) || []).map((commitment) => {
      const parts = [
        commitment.type,
        [money(commitment.amount, LOCALE, CURRENCY), commitment.frequency]
          .filter((p) => p)
          .join(' '),
        commitment.status
      ];
      if (commitment.balance !== null && commitment.balance !== undefined) {
        parts.push(fill(balanceText, money(commitment.balance, LOCALE, CURRENCY)));
      }
      return {
        key: commitment.id,
        url: `/${commitment.id}`,
        name: commitment.name,
        line: parts.filter((part) => part).join(', '),
        next: commitment.nextDueDate
          ? fill(
              nextText,
              money(commitment.nextDueAmount, LOCALE, CURRENCY),
              day(commitment.nextDueDate, LOCALE)
            )
          : ''
      };
    });
  }

  get hasCommitments() {
    return this.commitments.length > 0;
  }
}
