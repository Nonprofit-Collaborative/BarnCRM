import { LightningElement, api } from 'lwc';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getInvoiceActions from '@salesforce/apex/ProjectBillingController.getInvoiceActions';
import sendInvoice from '@salesforce/apex/ProjectBillingController.sendInvoice';
import markPaid from '@salesforce/apex/ProjectBillingController.markPaid';
import voidInvoice from '@salesforce/apex/ProjectBillingController.voidInvoice';
import printInvoice from '@salesforce/apex/ProjectBillingController.printInvoice';
import sendPaymentLink from '@salesforce/apex/ProjectBillingController.sendPaymentLink';
import { localIsoDate, messageFrom } from 'c/findCsv';
import { iconFor } from 'c/barnIcons';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const PKG = 'Projects';

/**
 * The invoice page's actions (PM-10, R-PM17, R-PM22): Send on a Draft; Mark Paid with a date and,
 * with BarnCRM Payments, Send Payment Link on a Sent invoice; Print (a PDF to Files) and Void on
 * any that is not Void. Shown with Create invoices on, to Manage Projects holders.
 */
export default class ProjectsInvoiceActions extends LightningElement {
  @api recordId;
  helpReady = isHelpLoaded([PKG]);
  icon = iconFor('Project_Invoice__c');
  actions;
  paidDate = localIsoDate();
  confirmingVoid = false;
  isWorking = false;
  errorMessage;
  notice;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp([PKG]).then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  get labels() {
    return {
      title: helpText('Projects', 'Projects_Invoice_ActionsTitle'),
      send: helpText('Projects', 'Projects_Invoice_Send'),
      markPaid: helpText('Projects', 'Projects_Invoice_MarkPaid'),
      paidDate: helpText('Projects', 'Projects_Invoice_PaidDate'),
      print: helpText('Projects', 'Projects_Invoice_Print'),
      voidInvoice: helpText('Projects', 'Projects_Invoice_Void'),
      voidConfirm: helpText('Projects', 'Projects_Invoice_VoidConfirm'),
      cancel: helpText('Projects', 'Projects_Board_Cancel'),
      payLink: helpText('Projects', 'Projects_Invoice_SendLink'),
      done: helpText('Projects', 'Projects_Invoice_Done'),
      printed: helpText('Projects', 'Projects_Invoice_Printed')
    };
  }

  get isShown() {
    return this.helpReady && this.actions?.canManage === true;
  }

  get isDraft() {
    return this.actions?.status === 'Draft';
  }

  get isSent() {
    return this.actions?.status === 'Sent';
  }

  get isOpen() {
    return this.actions && this.actions.status !== 'Void';
  }

  get canPayOnline() {
    return this.isSent && this.actions.online === true && this.actions.balance > 0;
  }

  async load() {
    try {
      this.actions = await getInvoiceActions({ invoiceId: this.recordId });
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  handlePaidDate(event) {
    this.paidDate = event.target.value;
  }

  handleAskVoid() {
    this.confirmingVoid = true;
  }

  handleCancelVoid() {
    this.confirmingVoid = false;
  }

  handleSend() {
    this.run(() => sendInvoice({ invoiceId: this.recordId }));
  }

  handleMarkPaid() {
    this.run(() => markPaid({ invoiceId: this.recordId, paidDate: this.paidDate }));
  }

  handleVoid() {
    this.confirmingVoid = false;
    this.run(() => voidInvoice({ invoiceId: this.recordId }));
  }

  handlePrint() {
    this.run(() => printInvoice({ invoiceId: this.recordId }), this.labels.printed);
  }

  handlePayLink() {
    this.run(() => sendPaymentLink({ invoiceId: this.recordId }), null);
  }

  /**
   * Runs one action and shows `message`, or, when it is null, the message the action returned;
   * then reloads the actions and the record.
   */
  async run(action, message = this.labels.done) {
    this.isWorking = true;
    try {
      const result = await action();
      this.notice = message ?? result;
      this.errorMessage = undefined;
      await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
      await this.load();
    } catch (error) {
      this.notice = undefined;
      this.errorMessage = messageFrom(error);
    } finally {
      this.isWorking = false;
    }
  }
}
