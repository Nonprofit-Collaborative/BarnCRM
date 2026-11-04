import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';

/**
 * Enter a Gift (people-giving-12): the Contact.Enter_Gift and Account.Enter_Gift actions open
 * Quick Gift Entry in the action window with the donor filled in, so a gift entered from a
 * donor's page gets the same form as everywhere else (in-kind, Pays a scheduled payment, Fund,
 * tribute and match). Save closes the window and refreshes the donor's page; Save and New keeps
 * it open for the next gift.
 */
export default class QuickGiftEntryAction extends LightningElement {
  @api recordId;
  @api objectApiName;

  async handleGiftSaved(event) {
    if (event.detail && event.detail.startAnother) {
      return;
    }
    try {
      if (this.recordId) {
        await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
      }
    } finally {
      this.dispatchEvent(new CloseActionScreenEvent());
    }
  }
}
