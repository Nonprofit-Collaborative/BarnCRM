import { LightningElement, api, wire } from 'lwc';
import Toast from 'lightning/toast';
import { CloseActionScreenEvent } from 'lightning/actions';
import {
  getRecord,
  getFieldValue,
  notifyRecordUpdateAvailable,
  updateRecord
} from 'lightning/uiRecordApi';
import CANCEL_PENDING_GIFT from '@salesforce/label/c.Giving_QuickStatus_CancelPendingGift';
import THANK_AGAIN from '@salesforce/label/c.Giving_QuickStatus_ThankAgain';
import DO_NOT_THANK from '@salesforce/label/c.Giving_QuickStatus_DoNotThank';
import REOPEN_ASK from '@salesforce/label/c.Giving_AskPipeline_ReopenAsk';
import MARK_PLAN_COMPLETE from '@salesforce/label/c.Giving_QuickStatus_MarkPlanComplete';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import CLOSE from '@salesforce/label/c.Core_BulkUpdate_Close';
import { bodyMessage } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { fieldId, quickStatus, updateInput } from './quickStatusActions';

const TITLES = {
  cancelPendingGift: CANCEL_PENDING_GIFT,
  thankAgain: THANK_AGAIN,
  doNotThank: DO_NOT_THANK,
  reopenAsk: REOPEN_ASK,
  markPlanComplete: MARK_PLAN_COMPLETE
};

/**
 * The window behind each one-step status quick action (people-giving-19): Cancel Pending Gift,
 * Thank Again and Do Not Thank on a gift, Reopen Ask on an ask, Mark Plan Complete on a
 * stewardship plan. A thin quick action component names the action; this reads the field,
 * asks a one-line question, and saves the one field through the platform, so the object's own
 * rules and the person's access decide. Where the change does not apply (a received gift, an
 * open ask) it says why and offers only Close, because a page layout action cannot be hidden
 * by the record's values.
 */
export default class GivingQuickStatus extends LightningElement {
  @api recordId;
  /** The name of the change, a key of QUICK_STATUS. */
  @api action;

  helpReady = isHelpLoaded('Giving');
  current;
  loaded = false;
  busy = false;
  errorMessage;

  labels = { cancel: CANCEL, close: CLOSE };

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Giving').then(() => {
        this.helpReady = true;
      });
    }
  }

  get definition() {
    return quickStatus(this.action);
  }

  get fields() {
    return this.definition ? [fieldId(this.definition)] : undefined;
  }

  @wire(getRecord, { recordId: '$recordId', fields: '$fields' })
  wiredRecord({ data, error }) {
    if (data) {
      this.current = getFieldValue(data, this.definition.field);
      this.errorMessage = undefined;
      this.loaded = true;
    } else if (error) {
      this.errorMessage = bodyMessage(error, helpText('Giving', 'Giving_Gift_UnexpectedError'));
      this.loaded = true;
    }
  }

  get title() {
    return TITLES[this.action];
  }

  get ready() {
    return this.loaded && this.helpReady;
  }

  get applies() {
    return (
      Boolean(this.definition) && !this.errorMessage && this.definition.appliesFrom(this.current)
    );
  }

  get confirmText() {
    return this.definition.confirm();
  }

  get notApplicableText() {
    return this.definition.notApplicable();
  }

  get showNotApplicable() {
    return Boolean(this.definition) && !this.errorMessage && !this.applies;
  }

  get confirmVariant() {
    return this.definition && this.definition.destructive ? 'destructive' : 'brand';
  }

  get dismissLabel() {
    return this.applies ? this.labels.cancel : this.labels.close;
  }

  async handleConfirm() {
    this.busy = true;
    this.errorMessage = undefined;
    try {
      await updateRecord(updateInput(this.definition, this.recordId));
      await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
      Toast.show({ label: this.definition.done(), variant: 'success' }, this);
      this.close();
    } catch (error) {
      // The object's own rule says why (for example, a gift that is no longer Pending).
      this.errorMessage = bodyMessage(error, helpText('Giving', 'Giving_Gift_UnexpectedError'));
    } finally {
      this.busy = false;
    }
  }

  handleDismiss() {
    this.close();
  }

  close() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }
}
