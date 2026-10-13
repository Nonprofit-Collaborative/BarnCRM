import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import Toast from 'lightning/toast';
import { refreshApex } from '@salesforce/apex';
import getGiftReceiptState from '@salesforce/apex/ReceiptController.getGiftReceiptState';
import issueReceipt from '@salesforce/apex/ReceiptController.issue';
import voidAndReissue from '@salesforce/apex/ReceiptController.voidAndReissue';

import TITLE from '@salesforce/label/c.Giving_Receipt_PanelTitle';
import COLUMN_NUMBER from '@salesforce/label/c.Giving_Receipt_ColumnNumber';
import COLUMN_STATUS from '@salesforce/label/c.Giving_Receipt_ColumnStatus';
import COLUMN_AMOUNT from '@salesforce/label/c.Giving_Receipt_ColumnAmount';
import COLUMN_ISSUED from '@salesforce/label/c.Giving_Receipt_ColumnIssued';
import COLUMN_VOID_REASON from '@salesforce/label/c.Giving_Receipt_ColumnVoidReason';
import COLUMN_FILE from '@salesforce/label/c.Giving_Receipt_ColumnFile';
import NONE_YET from '@salesforce/label/c.Giving_Receipt_NoneYet';
import ISSUE from '@salesforce/label/c.Giving_Receipt_IssueButton';
import VOID_REASON from '@salesforce/label/c.Giving_Receipt_VoidReasonField';
import VOID_AND_REISSUE from '@salesforce/label/c.Giving_Receipt_VoidAndReissueButton';
import VOID_NOTE from '@salesforce/label/c.Giving_Receipt_VoidNote';
import VIEW_PDF from '@salesforce/label/c.Giving_Receipt_ViewPdf';
import VIEW_PDF_OF from '@salesforce/label/c.Giving_Receipt_ViewPdfOf';
import ISSUED_TITLE from '@salesforce/label/c.Giving_Receipt_IssuedTitle';
import ISSUED_MESSAGE from '@salesforce/label/c.Giving_Receipt_IssuedMessage';
import NOT_ISSUED_TITLE from '@salesforce/label/c.Giving_Receipt_NotIssuedTitle';
import REASON_NEEDED_TITLE from '@salesforce/label/c.Giving_Receipt_ReasonNeededTitle';
import REASON_NEEDED from '@salesforce/label/c.Giving_Receipt_VoidNeedsReason';
import REISSUED_TITLE from '@salesforce/label/c.Giving_Receipt_ReissuedTitle';
import REISSUED_MESSAGE from '@salesforce/label/c.Giving_Receipt_ReissuedMessage';
import NOT_REISSUED_TITLE from '@salesforce/label/c.Giving_Receipt_NotReissuedTitle';
import UNEXPECTED_ERROR from '@salesforce/label/c.Giving_Receipt_UnexpectedError';

/**
 * Issuing, voiding and reissuing a receipt from the gift's own page.
 *
 * One panel rather than two buttons, because the second thing a person wants after issuing a
 * receipt is to see it, and the thing they want after finding a mistake is to see both documents
 * side by side. So every receipt with a file has a View PDF link, which opens the standard file
 * preview rather than a download URL built by hand. A void is never offered without a reason
 * box: a void with no reason is the record an auditor cannot use.
 */
export default class ReceiptActions extends NavigationMixin(LightningElement) {
  @api recordId;

  labels = {
    title: TITLE,
    columnNumber: COLUMN_NUMBER,
    columnStatus: COLUMN_STATUS,
    columnAmount: COLUMN_AMOUNT,
    columnIssued: COLUMN_ISSUED,
    columnVoidReason: COLUMN_VOID_REASON,
    columnFile: COLUMN_FILE,
    noneYet: NONE_YET,
    issue: ISSUE,
    voidReason: VOID_REASON,
    voidAndReissue: VOID_AND_REISSUE,
    voidNote: VOID_NOTE,
    viewPdf: VIEW_PDF
  };

  state;
  wiredState;
  reason = '';
  working = false;
  loadError;

  @wire(getGiftReceiptState, { giftId: '$recordId' })
  handleState(result) {
    this.wiredState = result;
    if (result.data) {
      this.state = result.data;
      this.loadError = undefined;
    } else if (result.error) {
      this.loadError = this.messageOf(result.error);
    }
  }

  get receipts() {
    return this.state ? this.state.receipts : [];
  }

  get rows() {
    return this.receipts.map((receipt) => ({
      ...receipt,
      viewPdfTitle: VIEW_PDF_OF.replace('{0}', receipt.receiptNumber)
    }));
  }

  get hasReceipts() {
    return this.receipts.length > 0;
  }

  get canIssue() {
    return !!this.state && this.state.canIssue && !this.state.alreadyReceipted;
  }

  get canReissue() {
    return !!this.state && this.state.canIssue && this.state.alreadyReceipted;
  }

  get busy() {
    return this.working;
  }

  get issuedReceipt() {
    return this.receipts.find((receipt) => receipt.status === 'Issued');
  }

  handleReasonChange(event) {
    this.reason = event.detail.value;
  }

  handleViewPdf(event) {
    const documentId = event.currentTarget.dataset.documentId;
    this[NavigationMixin.Navigate]({
      type: 'standard__namedPage',
      attributes: { pageName: 'filePreview' },
      state: { recordIds: documentId, selectedRecordId: documentId }
    });
  }

  async handleIssue() {
    this.working = true;
    try {
      const receipt = await issueReceipt({ giftId: this.recordId });
      this.toast(ISSUED_TITLE, ISSUED_MESSAGE.replace('{0}', receipt.receiptNumber), 'success');
      await refreshApex(this.wiredState);
    } catch (error) {
      this.toast(NOT_ISSUED_TITLE, this.messageOf(error), 'error');
    } finally {
      this.working = false;
    }
  }

  async handleVoidAndReissue() {
    if (!this.reason || !this.reason.trim()) {
      this.toast(REASON_NEEDED_TITLE, REASON_NEEDED, 'warning');
      return;
    }
    const current = this.issuedReceipt;
    if (!current) {
      return;
    }
    this.working = true;
    try {
      const replacement = await voidAndReissue({
        receiptId: current.id,
        reason: this.reason
      });
      this.toast(
        REISSUED_TITLE,
        REISSUED_MESSAGE.replace('{0}', current.receiptNumber).replace(
          '{1}',
          replacement.receiptNumber
        ),
        'success'
      );
      this.reason = '';
      await refreshApex(this.wiredState);
    } catch (error) {
      this.toast(NOT_REISSUED_TITLE, this.messageOf(error), 'error');
    } finally {
      this.working = false;
    }
  }

  messageOf(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    return UNEXPECTED_ERROR;
  }

  toast(title, message, variant) {
    Toast.show({ label: title, message, variant }, this);
  }
}
