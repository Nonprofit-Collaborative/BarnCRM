import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getCalendar from '@salesforce/apex/GrantCalendarController.getCalendar';
import { monthRange, monthWeeks, shiftMonth, weekdayOrder } from 'c/grantCalendarModel';
import { messageFrom } from 'c/findCsv';
import { iconFor } from 'c/barnIcons';
import { printPage } from 'c/fundersPrint';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import LOCALE from '@salesforce/i18n/locale';
import CURRENCY from '@salesforce/i18n/currency';
import FIRST_DAY_OF_WEEK from '@salesforce/i18n/firstDayOfWeek';

import TITLE from '@salesforce/label/c.Funders_Calendar_Title';
import PREVIOUS from '@salesforce/label/c.Funders_Calendar_Previous';
import NEXT from '@salesforce/label/c.Funders_Calendar_Next';
import PRINT from '@salesforce/label/c.Funders_Shared_Print';
import SCOPE_EVERYONE from '@salesforce/label/c.Funders_Pipeline_ScopeEveryone';
import SCOPE_MINE from '@salesforce/label/c.Funders_Pipeline_ScopeMine';
import KIND_APPLICATION_LABEL from '@salesforce/label/c.Funders_Pipeline_KindApplication';
import OVERDUE from '@salesforce/label/c.Core_HubHome_BadgeOverdue';

const KIND_REQUIREMENT = 'requirement';
const KIND_PAYMENT = 'payment';
const OBJECT_BY_KIND = {
  application: 'Grant__c',
  requirement: 'Grant_Requirement__c',
  payment: 'Grant_Payment__c'
};
const CLASS_BY_KIND = {
  application: 'barn-item barn-item_application slds-size_full',
  requirement: 'barn-item barn-item_requirement slds-size_full',
  payment: 'barn-item barn-item_payment slds-size_full'
};

const messageOf = (error) => messageFrom(error, helpText('Funders', 'Funders_Calendar_LoadFailed'));

/** Salesforce counts the first day of the week from 1 for Sunday; the model from 0. */
const firstDay = () => {
  const day = Number(FIRST_DAY_OF_WEEK);
  return day >= 1 && day <= 7 ? day - 1 : 0;
};

/**
 * The Grant Calendar tab (F-08, ADR-0162 `0162-funders-restricted-funds-schedules-calendar.md`
 * decision 8): a month at a time, the application deadlines of grants not yet submitted, the due
 * dates of open requirements and the expected payments, for everyone or the person's own. Each
 * entry opens its record.
 *
 * The weeks are worked out by the framework-free `grantCalendarModel`, which sorts and marks
 * overdue rows with the Grant Pipeline's own `deadlineRows`; this component only draws them.
 */
export default class GrantCalendar extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded('Funders');

  labels = {
    title: TITLE,
    get intro() {
      return helpText('Funders', 'Funders_Calendar_Intro');
    },
    previous: PREVIOUS,
    next: NEXT,
    scope: SCOPE_EVERYONE,
    overdue: OVERDUE,
    print: PRINT
  };

  icon = iconFor('Grant_Calendar');

  kindLabels = { requirement: '', payment: '' };

  scopeOptions = [
    { label: SCOPE_EVERYONE, value: 'all' },
    { label: SCOPE_MINE, value: 'mine' }
  ];

  scope = 'all';
  year;
  month;
  weeks = [];
  isLoading = true;
  errorMessage;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Funders').then(() => {
        this.helpReady = true;
      });
    }
    const now = new Date();
    this.year = now.getFullYear();
    this.month = now.getMonth() + 1;
    this.load();
  }

  get monthTitle() {
    return new Intl.DateTimeFormat(LOCALE, {
      month: 'long',
      year: 'numeric',
      timeZone: 'UTC'
    }).format(new Date(Date.UTC(this.year, this.month - 1, 1)));
  }

  /** What each border colour means, and the overdue mark (vis-modules-9). */
  get legend() {
    return [
      { key: 'application', text: KIND_APPLICATION_LABEL },
      { key: 'requirement', text: this.kindLabels.requirement },
      { key: 'payment', text: this.kindLabels.payment }
    ]
      .filter((entry) => entry.text)
      .map((entry) => ({ ...entry, swatchClass: `barn-swatch barn-item_${entry.key}` }));
  }

  get weekdays() {
    const format = new Intl.DateTimeFormat(LOCALE, { weekday: 'short', timeZone: 'UTC' });
    // 2023-01-01 was a Sunday, so day n of the week is January 1 + n.
    return weekdayOrder(firstDay()).map((day) => ({
      key: String(day),
      name: format.format(new Date(Date.UTC(2023, 0, 1 + day)))
    }));
  }

  async load() {
    this.isLoading = true;
    const range = monthRange(this.year, this.month, firstDay());
    try {
      const calendar = await getCalendar({
        fromDate: range.from,
        toDate: range.to,
        mineOnly: this.scope === 'mine'
      });
      this.errorMessage = undefined;
      this.kindLabels = {
        requirement: calendar.requirementLabel || '',
        payment: calendar.paymentLabel || ''
      };
      this.weeks = this.decorate(
        monthWeeks(this.year, this.month, calendar.rows, calendar.today, firstDay()),
        calendar.paymentLabel
      );
    } catch (error) {
      this.errorMessage = messageOf(error);
      this.weeks = [];
    } finally {
      this.isLoading = false;
    }
  }

  decorate(weeks, paymentLabel) {
    return weeks.map((week) => ({
      ...week,
      days: week.days.map((day) => ({
        ...day,
        cellClass: [
          'barn-day',
          day.inMonth ? '' : 'barn-day_outside',
          day.isToday ? 'barn-day_today' : '',
          day.items.length ? '' : 'barn-day_empty'
        ]
          .filter(Boolean)
          .join(' '),
        items: day.items.map((item) => ({
          ...item,
          objectApiName: OBJECT_BY_KIND[item.kind] || 'Grant__c',
          // Overdue is an icon and words, never colour alone (vis-modules-9): red text on the
          // item's grey failed contrast.
          itemClass: `${CLASS_BY_KIND[item.kind] || CLASS_BY_KIND.application}${
            item.overdue ? ' barn-item_overdue' : ''
          }`,
          text: this.textOf(item, paymentLabel),
          title: item.overdue
            ? `${OVERDUE}: ${this.textOf(item, paymentLabel)}`
            : this.textOf(item, paymentLabel)
        }))
      }))
    }));
  }

  textOf(item, paymentLabel) {
    if (item.kind === KIND_REQUIREMENT) {
      return `${item.requirementType || ''}: ${item.grantName || ''}`;
    }
    if (item.kind === KIND_PAYMENT) {
      const amount =
        item.amount === null || item.amount === undefined
          ? ''
          : ` ${this.formatMoney(item.amount)}`;
      return `${paymentLabel || ''}: ${item.grantName || ''}${amount}`;
    }
    return `${KIND_APPLICATION_LABEL}: ${item.name || ''}`;
  }

  /** A payment amount as money in the person's currency (vis-modules-8). */
  formatMoney(amount) {
    try {
      return new Intl.NumberFormat(LOCALE, {
        style: 'currency',
        currency: CURRENCY || 'USD'
      }).format(amount);
    } catch {
      // An unknown currency code: the number alone.
      return new Intl.NumberFormat(LOCALE, { maximumFractionDigits: 2 }).format(amount);
    }
  }

  handlePrint() {
    printPage(this);
  }

  handleScope(event) {
    this.scope = event.detail.value;
    this.load();
  }

  handlePrevious() {
    this.moveMonth(-1);
  }

  handleNext() {
    this.moveMonth(1);
  }

  moveMonth(delta) {
    const shifted = shiftMonth(this.year, this.month, delta);
    this.year = shifted.year;
    this.month = shifted.month;
    this.load();
  }

  handleOpen(event) {
    const { recordId, object } = event.currentTarget.dataset;
    this[NavigationMixin.Navigate]({
      type: 'standard__recordPage',
      attributes: { recordId, objectApiName: object, actionName: 'view' }
    });
  }
}
