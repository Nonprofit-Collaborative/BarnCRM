import { LightningElement, api, wire } from 'lwc';
import Toast from 'lightning/toast';
import { CloseActionScreenEvent } from 'lightning/actions';
import getGiftSummary from '@salesforce/apex/GiftController.getGiftSummary';
import refundGift from '@salesforce/apex/GiftController.refund';
import writeOffGift from '@salesforce/apex/GiftController.writeOff';

import HEADING from '@salesforce/label/c.Giving_RefundGift_Heading';
import AMOUNT_LABEL from '@salesforce/label/c.Giving_RefundGift_AmountLabel';
import REASON_LABEL from '@salesforce/label/c.Giving_RefundGift_ReasonLabel';
import REMAINING_LABEL from '@salesforce/label/c.Giving_RefundGift_RemainingLabel';
import MODE_REFUND from '@salesforce/label/c.Giving_RefundGift_ModeRefund';
import MODE_WRITE_OFF from '@salesforce/label/c.Giving_RefundGift_ModeWriteOff';
import CONFIRM from '@salesforce/label/c.Giving_RefundGift_Confirm';
import CANCEL from '@salesforce/label/c.Giving_RefundGift_Cancel';
import SUCCESS from '@salesforce/label/c.Giving_RefundGift_Success';
import REASON_REQUIRED from '@salesforce/label/c.Giving_RefundGift_ReasonRequired';
import NO_ACCESS from '@salesforce/label/c.Giving_RefundGift_NoPermission';

const REFUND = 'refund';
const WRITE_OFF = 'writeOff';

/**
 * Records money going back to a donor, from the gift's own page. Both a refund of part or all
 * of a gift and a write-off of what is left are one linked negative gift, so they are one
 * screen with a choice at the top rather than two buttons that look unrelated.
 */
export default class GiftRefund extends LightningElement {
  @api recordId;

  labels = {
    heading: HEADING,
    amount: AMOUNT_LABEL,
    reason: REASON_LABEL,
    remaining: REMAINING_LABEL,
    modeRefund: MODE_REFUND,
    modeWriteOff: MODE_WRITE_OFF,
    confirm: CONFIRM,
    cancel: CANCEL,
    noAccess: NO_ACCESS
  };

  mode = REFUND;
  amount;
  reason = '';
  remainingAmount;
  working = false;
  loadError;
  canRefund;

  /**
   * A person who may read the gift but not record money going back is told so, and offered
   * nothing that could only fail. Until the summary arrives the form shows as usual.
   */
  get noAccess() {
    return this.canRefund === false;
  }

  get canEnter() {
    return !this.noAccess;
  }

  get modeOptions() {
    return [
      { label: MODE_REFUND, value: REFUND },
      { label: MODE_WRITE_OFF, value: WRITE_OFF }
    ];
  }

  get isWriteOff() {
    return this.mode === WRITE_OFF;
  }

  /** A refund asks how much goes back; a write-off has no amount to type. */
  get showAmount() {
    return !this.isWriteOff;
  }

  get confirmDisabled() {
    return this.working || this.remainingAmount === undefined;
  }

  @wire(getGiftSummary, { giftId: '$recordId' })
  loadSummary({ data, error }) {
    if (data) {
      this.remainingAmount = data.remainingAmount;
      this.canRefund = data.canRefund !== false;
      // The amount going back is almost always the whole of what is left, so that is what
      // the field starts at and David only types when it is not.
      if (this.amount === undefined) {
        this.amount = data.remainingAmount;
      }
      this.loadError = undefined;
    } else if (error) {
      this.loadError = this.messageOf(error);
    }
  }

  handleModeChange(event) {
    this.mode = event.detail.value;
  }

  handleAmountChange(event) {
    this.amount = event.detail ? event.detail.value : undefined;
  }

  handleReasonChange(event) {
    this.reason = event.detail ? event.detail.value : '';
  }

  handleCancel() {
    this.close();
  }

  async handleConfirm() {
    if (!this.reason || !this.reason.trim()) {
      this.toast(REASON_REQUIRED, 'error');
      return;
    }
    this.working = true;
    try {
      if (this.isWriteOff) {
        await writeOffGift({ giftId: this.recordId, reason: this.reason });
      } else {
        await refundGift({
          giftId: this.recordId,
          amount: this.amount === undefined ? null : Number(this.amount),
          reason: this.reason
        });
      }
      this.toast(SUCCESS, 'success');
      this.close();
    } catch (error) {
      this.toast(this.messageOf(error), 'error');
    } finally {
      this.working = false;
    }
  }

  messageOf(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    return error && error.message ? error.message : String(error);
  }

  toast(message, variant) {
    Toast.show({ label: message, variant }, this);
  }

  close() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }
}
