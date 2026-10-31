import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getTribute from '@salesforce/apex/TributeController.getTribute';
import markNotificationSent from '@salesforce/apex/TributeController.markNotificationSent';

import TITLE from '@salesforce/label/c.Giving_TributeNotification_Title';
import NONE from '@salesforce/label/c.Giving_TributeNotification_None';
import MARK_SENT from '@salesforce/label/c.Giving_TributeNotification_MarkSent';
import SENT from '@salesforce/label/c.Giving_TributeNotification_Sent';
import NOT_SENT from '@salesforce/label/c.Giving_TributeNotification_NotSent';
import NOTIFY_PREFIX from '@salesforce/label/c.Giving_TributeNotification_NotifyPrefix';
import ACTION_FAILED from '@salesforce/label/c.Giving_TributeNotification_ActionFailed';
import { bodyMessage } from 'c/findCsv';

export default class TributeNotification extends LightningElement {
  @api recordId;

  labels = {
    title: TITLE,
    none: NONE,
    markSent: MARK_SENT,
    sent: SENT,
    notSent: NOT_SENT,
    notifyPrefix: NOTIFY_PREFIX
  };

  tribute;
  wiredTribute;
  errorMessage;
  busy = false;

  @wire(getTribute, { giftId: '$recordId' })
  wiredResult(result) {
    this.wiredTribute = result;
    if (result.data !== undefined) {
      this.tribute = result.data;
      this.errorMessage = undefined;
    }
    if (result.error) {
      this.errorMessage = bodyMessage(result.error, ACTION_FAILED);
    }
  }

  get hasTribute() {
    return !!this.tribute;
  }

  get isEmpty() {
    return this.tribute === null;
  }

  /**
   * The one line David reads before posting a letter: what the gift honors and who hears about
   * it. The amount is never part of it (R-TR5).
   */
  get summary() {
    if (!this.tribute) {
      return '';
    }
    const parts = [[this.tribute.tributeType, this.tribute.honoreeName].filter(Boolean).join(' ')];
    if (this.tribute.recipientName) {
      parts.push(`${this.labels.notifyPrefix} ${this.tribute.recipientName}`);
    }
    return parts.join(', ');
  }

  get statusText() {
    if (!this.tribute) {
      return '';
    }
    return this.tribute.notificationSent ? this.labels.sent : this.labels.notSent;
  }

  get blockedReason() {
    return this.tribute ? this.tribute.blockedReason : undefined;
  }

  get showBlockedReason() {
    return !!this.blockedReason;
  }

  get showMarkSent() {
    return !!(this.tribute && this.tribute.canMarkSent);
  }

  get markSentDisabled() {
    return this.busy;
  }

  get hasError() {
    return !!this.errorMessage;
  }

  handleMarkSent() {
    this.busy = true;
    this.errorMessage = undefined;
    return markNotificationSent({ tributeId: this.tribute.recordId })
      .then((tribute) => {
        this.tribute = tribute;
        return refreshApex(this.wiredTribute);
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, ACTION_FAILED);
      })
      .finally(() => {
        this.busy = false;
      });
  }
}
