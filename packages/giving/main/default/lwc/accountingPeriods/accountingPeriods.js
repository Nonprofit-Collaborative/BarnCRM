import { LightningElement } from 'lwc';
import getPeriod from '@salesforce/apex/AccountingPeriodController.getPeriod';
import closeThrough from '@salesforce/apex/AccountingPeriodController.closeThrough';

import TITLE from '@salesforce/label/c.Giving_Periods_Title';
import INTRO from '@salesforce/label/c.Giving_Periods_Intro';
import CLOSED_THROUGH_HEADING from '@salesforce/label/c.Giving_Periods_ClosedThroughHeading';
import NOT_CLOSED from '@salesforce/label/c.Giving_Periods_NotClosed';
import SAVE_BUTTON from '@salesforce/label/c.Giving_Periods_SaveButton';
import SAVED from '@salesforce/label/c.Giving_Periods_Saved';
import REOPEN_NOTE from '@salesforce/label/c.Giving_Periods_ReopenNote';
import READ_ONLY from '@salesforce/label/c.Giving_Periods_ReadOnly';
import UNEXPECTED_ERROR from '@salesforce/label/c.Giving_Periods_UnexpectedError';
import { bodyMessage } from 'c/findCsv';

/**
 * The Accounting Periods page (G-20, ADR-0053), reached from the Giving section of the Nonprofit
 * Settings console.
 *
 * It shows the date the books are closed through and moves it. The rules live in the controller:
 * the date moves forward only, never past the day before yesterday, and moving it back needs Override Posting
 * Lock. The page only offers the field to someone who can use it and shows what the controller
 * says when it refuses.
 */
export default class AccountingPeriods extends LightningElement {
  labels = {
    title: TITLE,
    intro: INTRO,
    closedThroughHeading: CLOSED_THROUGH_HEADING,
    notClosed: NOT_CLOSED,
    save: SAVE_BUTTON,
    reopenNote: REOPEN_NOTE,
    readOnly: READ_ONLY
  };

  view;
  draftDate;
  errorMessage;
  noticeMessage;
  busy = false;

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      this.show(await getPeriod());
    } catch (error) {
      this.errorMessage = bodyMessage(error, UNEXPECTED_ERROR);
    }
  }

  show(view) {
    this.view = view;
    this.draftDate = view ? view.closedThrough : undefined;
  }

  get loaded() {
    return !!this.view;
  }

  get closedThrough() {
    return this.view ? this.view.closedThrough : undefined;
  }

  get isClosed() {
    return !!this.closedThrough;
  }

  get canManage() {
    return !!(this.view && this.view.canManage);
  }

  get showReadOnlyNote() {
    return this.loaded && !this.canManage;
  }

  get latestAllowed() {
    return this.view ? this.view.latestAllowed : undefined;
  }

  get saveDisabled() {
    return this.busy || !this.draftDate || this.draftDate === this.closedThrough;
  }

  handleDateChange(event) {
    this.draftDate = event.detail.value;
    this.noticeMessage = undefined;
  }

  async handleSave() {
    this.busy = true;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    try {
      this.show(await closeThrough({ closeDate: this.draftDate }));
      this.noticeMessage = SAVED;
    } catch (error) {
      this.errorMessage = bodyMessage(error, UNEXPECTED_ERROR);
    } finally {
      this.busy = false;
    }
  }
}
