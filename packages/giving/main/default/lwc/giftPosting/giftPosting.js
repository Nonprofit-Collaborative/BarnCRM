import { LightningElement, api } from 'lwc';
import getState from '@salesforce/apex/GiftPostingController.getState';
import unpost from '@salesforce/apex/GiftPostingController.unpost';

import TITLE from '@salesforce/label/c.Giving_PostingCard_Title';
import POSTED_BY from '@salesforce/label/c.Giving_PostingCard_PostedBy';
import NOT_POSTED from '@salesforce/label/c.Giving_PostingCard_NotPosted';
import NOT_IN_BOOKS from '@salesforce/label/c.Giving_PostingCard_NotInBooks';
import CLOSED_PERIOD from '@salesforce/label/c.Giving_PostingCard_ClosedPeriod';
import REASON_LABEL from '@salesforce/label/c.Giving_PostingCard_ReasonLabel';
import UNPOST_BUTTON from '@salesforce/label/c.Giving_PostingCard_UnpostButton';
import UNPOSTED from '@salesforce/label/c.Giving_PostingCard_Unposted';
import REASON_REQUIRED from '@salesforce/label/c.Giving_Posting_ReasonRequired';
import UNEXPECTED_ERROR from '@salesforce/label/c.Giving_Periods_UnexpectedError';
import { bodyMessage } from 'c/findCsv';

/**
 * The Posting card on a gift's page (G-20, ADR-0053).
 *
 * A person about to change a gift sees here why they cannot: it is posted, or it is dated in a
 * closed period. The bookkeeper unposts it from here, and only with a reason, because an unpost
 * nobody can explain is the change an auditor cannot use.
 */
export default class GiftPosting extends LightningElement {
  @api recordId;

  labels = {
    title: TITLE,
    postedBy: POSTED_BY,
    notPosted: NOT_POSTED,
    notInBooks: NOT_IN_BOOKS,
    closedPeriod: CLOSED_PERIOD,
    reasonLabel: REASON_LABEL,
    unpost: UNPOST_BUTTON
  };

  state;
  reason = '';
  busy = false;
  errorMessage;
  noticeMessage;

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      this.state = await getState({ giftId: this.recordId });
    } catch (error) {
      this.errorMessage = bodyMessage(error, UNEXPECTED_ERROR);
    }
  }

  get loaded() {
    return !!this.state;
  }

  get isPosted() {
    return !!(this.state && this.state.posted);
  }

  get showNotPosted() {
    return this.loaded && this.state.inBooks && !this.state.posted;
  }

  get showNotInBooks() {
    return this.loaded && !this.state.inBooks;
  }

  get inClosedPeriod() {
    return !!(this.state && this.state.inClosedPeriod);
  }

  get canUnpost() {
    return !!(this.state && this.state.canUnpost);
  }

  get unpostDisabled() {
    return this.busy || !this.reason.trim();
  }

  handleReasonChange(event) {
    this.reason = event.detail.value || '';
  }

  async handleUnpost() {
    if (!this.reason.trim()) {
      this.errorMessage = REASON_REQUIRED;
      return;
    }
    this.busy = true;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    try {
      this.state = await unpost({ giftId: this.recordId, reason: this.reason });
      this.reason = '';
      this.noticeMessage = UNPOSTED;
    } catch (error) {
      this.errorMessage = bodyMessage(error, UNEXPECTED_ERROR);
    } finally {
      this.busy = false;
    }
  }
}
