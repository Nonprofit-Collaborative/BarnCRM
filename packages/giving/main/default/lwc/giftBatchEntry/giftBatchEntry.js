import { LightningElement, api, wire } from 'lwc';
import { getRecord, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import FORM_FACTOR from '@salesforce/client/formFactor';

import CONTROL_TOTAL from '@salesforce/schema/Gift_Batch__c.Control_Total__c';
import STATUS from '@salesforce/schema/Gift_Batch__c.Status__c';
import FUND_OBJECT from '@salesforce/schema/Fund__c';
import APPEAL_OBJECT from '@salesforce/schema/Appeal__c';

import getBatch from '@salesforce/apex/GiftBatchController.getBatch';
import saveLines from '@salesforce/apex/GiftBatchController.saveLines';
import postBatch from '@salesforce/apex/GiftBatchController.postBatch';

import title from '@salesforce/label/c.Giving_GiftBatch_Title';
import controlTotalLabel from '@salesforce/label/c.Giving_GiftBatch_ControlTotalLabel';
import enteredLabel from '@salesforce/label/c.Giving_GiftBatch_EnteredLabel';
import balanced from '@salesforce/label/c.Giving_GiftBatch_Balanced';
import shortBy from '@salesforce/label/c.Giving_GiftBatch_ErrorShortOfControlTotal';
import overBy from '@salesforce/label/c.Giving_GiftBatch_ErrorOverControlTotal';
import noControlTotal from '@salesforce/label/c.Giving_GiftBatch_ErrorNoControlTotal';
import postedNote from '@salesforce/label/c.Giving_GiftBatch_PostedNote';
import columnLine from '@salesforce/label/c.Giving_GiftBatch_ColumnLine';
import columnDonor from '@salesforce/label/c.Giving_GiftBatch_ColumnDonor';
import columnAmount from '@salesforce/label/c.Giving_GiftBatch_ColumnAmount';
import columnReference from '@salesforce/label/c.Giving_GiftBatch_ColumnReference';
import columnDate from '@salesforce/label/c.Giving_GiftBatch_ColumnDate';
import columnMethod from '@salesforce/label/c.Giving_GiftBatch_ColumnMethod';
import columnFund from '@salesforce/label/c.Giving_GiftBatch_ColumnFund';
import columnAppeal from '@salesforce/label/c.Giving_GiftBatch_ColumnAppeal';
import columnGift from '@salesforce/label/c.Giving_GiftBatch_ColumnGift';
import fromBatch from '@salesforce/label/c.Giving_GiftBatch_FromBatch';
import fromBatchHelp from '@salesforce/label/c.Giving_GiftBatch_FromBatchHelp';
import person from '@salesforce/label/c.Giving_GiftBatch_Person';
import organization from '@salesforce/label/c.Giving_GiftBatch_Organization';
import donorPlaceholder from '@salesforce/label/c.Giving_GiftBatch_DonorPlaceholder';
import removeLine from '@salesforce/label/c.Giving_GiftBatch_RemoveLine';
import cellLabel from '@salesforce/label/c.Giving_GiftBatch_CellLabel';
import donorKind from '@salesforce/label/c.Giving_GiftBatch_DonorKind';
import useComputer from '@salesforce/label/c.Giving_GiftBatch_UseComputer';
import addLine from '@salesforce/label/c.Giving_GiftBatch_AddLine';
import saveButton from '@salesforce/label/c.Giving_GiftBatch_Save';
import postButton from '@salesforce/label/c.Giving_GiftBatch_Post';
import working from '@salesforce/label/c.Giving_GiftBatch_Working';
import noLines from '@salesforce/label/c.Giving_GiftBatch_NoLines';
import unsaved from '@salesforce/label/c.Giving_GiftBatch_Unsaved';
import savedToast from '@salesforce/label/c.Giving_GiftBatch_Saved';
import postedToast from '@salesforce/label/c.Giving_GiftBatch_PostedToast';
import errorLoadBatch from '@salesforce/label/c.Giving_GiftBatch_ErrorLoadBatch';
import noAccess from '@salesforce/label/c.Giving_GiftBatch_ErrorNoAccess';
import errorSaveRows from '@salesforce/label/c.Giving_GiftBatch_ErrorSaveRows';
import errorPostFailed from '@salesforce/label/c.Giving_GiftBatch_ErrorPostFailed';

const FIELDS = [CONTROL_TOTAL, STATUS];
const PERSON = 'person';
const ORGANIZATION = 'organization';

let nextKey = 0;

/**
 * Gift batch entry (G-17): the grid of lines on a gift batch record page, the running total
 * against the deposit slip, and posting. The batch's own fields are edited on the page above;
 * this component reloads whenever they change, so the totals always compare against the
 * control total the page shows.
 */
export default class GiftBatchEntry extends LightningElement {
  @api recordId;

  labels = {
    title,
    controlTotalLabel,
    enteredLabel,
    postedNote,
    noAccess,
    columnLine,
    columnDonor,
    columnAmount,
    columnReference,
    columnDate,
    columnMethod,
    columnFund,
    columnAppeal,
    columnGift,
    fromBatchHelp,
    donorPlaceholder,
    addLine,
    saveButton,
    postButton,
    working,
    noLines,
    unsaved,
    useComputer
  };

  fundObject = FUND_OBJECT.objectApiName;
  appealObject = APPEAL_OBJECT.objectApiName;

  batch;
  lines = [];
  removedIds = [];
  lineErrors = {};
  formError;
  dirty = false;
  busy = false;

  @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
  wiredBatch({ data }) {
    if (data) {
      this.load();
    }
  }

  async load() {
    try {
      const view = await getBatch({ batchId: this.recordId });
      this.batch = view;
      if (!this.dirty) {
        this.lines = view.lines.map((line) => this.toLocal(line));
        this.removedIds = [];
      }
    } catch (error) {
      this.formError = messageOf(error, errorLoadBatch);
    }
  }

  toLocal(line) {
    return {
      ...line,
      key: line.id || `new-${nextKey++}`,
      kind: line.donorAccountId && !line.donorContactId ? ORGANIZATION : PERSON
    };
  }

  get loaded() {
    return Boolean(this.batch);
  }

  get posted() {
    return this.loaded && this.batch.posted;
  }

  /** Open, and this person may change it: someone who can only read it gets no buttons. */
  get editable() {
    return this.loaded && !this.batch.posted && this.batch.canEdit === true;
  }

  get locked() {
    return !this.editable;
  }

  get readOnly() {
    return this.loaded && !this.batch.posted && this.batch.canEdit !== true;
  }

  get hasLines() {
    return this.lines.length > 0;
  }

  get enteredTotal() {
    return this.lines.reduce((sum, line) => sum + (Number(line.amount) || 0), 0);
  }

  get controlTotal() {
    return this.batch?.controlTotal;
  }

  /** The balance, said in words, so it never depends on colour alone. */
  get balanceText() {
    if (this.controlTotal === null || this.controlTotal === undefined) {
      return noControlTotal;
    }
    const gap = Math.round((this.controlTotal - this.enteredTotal) * 100) / 100;
    if (gap === 0) {
      return balanced;
    }
    const amount = Math.abs(gap).toFixed(2);
    return (gap > 0 ? shortBy : overBy).replace('{0}', amount);
  }

  get isBalanced() {
    return this.balanceText === balanced;
  }

  get balanceClass() {
    return this.isBalanced ? 'slds-text-color_success' : 'slds-text-color_error';
  }

  get postDisabled() {
    return this.busy || !this.isBalanced || !this.hasLines;
  }

  get methodOptions() {
    const options = (this.batch?.paymentMethods || []).map((option) => ({ ...option }));
    return [{ label: fromBatch, value: '' }, ...options];
  }

  get kindOptions() {
    return [
      { label: person, value: PERSON },
      { label: organization, value: ORGANIZATION }
    ];
  }

  /** The grid is nine columns wide, so a phone gets a note that a computer is easier. */
  get isPhone() {
    return FORM_FACTOR === 'Small';
  }

  get showKind() {
    return this.loaded && !this.batch.hasPersonAccounts;
  }

  /** What each row of the grid draws. */
  get rows() {
    return this.lines.map((line, index) => ({
      ...line,
      number: index + 1,
      isPerson: line.kind === PERSON,
      donorObject: line.kind === PERSON && !this.batch?.hasPersonAccounts ? 'Contact' : 'Account',
      donorId:
        line.kind === PERSON && !this.batch?.hasPersonAccounts
          ? line.donorContactId
          : line.donorAccountId,
      methodValue: line.paymentMethod || '',
      giftUrl: line.giftId ? `/lightning/r/${line.giftId}/view` : null,
      errors: (this.lineErrors[line.id] || []).join(' '),
      hasErrors: Boolean(this.lineErrors[line.id]),
      cellLabels: this.cellLabelsFor(index + 1)
    }));
  }

  /**
   * Every row repeats the same inputs, so each hidden label carries the line number: a
   * screen reader then says "Amount, line 3" rather than "Amount" nine times over.
   */
  cellLabelsFor(number) {
    const label = (column) => cellLabel.replace('{0}', column).replace('{1}', number);
    return {
      kind: label(donorKind),
      donor: label(columnDonor),
      amount: label(columnAmount),
      reference: label(columnReference),
      date: label(columnDate),
      method: label(columnMethod),
      fund: label(columnFund),
      appeal: label(columnAppeal),
      remove: removeLine.replace('{0}', number)
    };
  }

  lineFor(event) {
    const key = event.target.dataset.key;
    return this.lines.find((line) => line.key === key);
  }

  change(event, apply) {
    const line = this.lineFor(event);
    if (!line) {
      return;
    }
    apply(line, event.detail);
    this.lines = [...this.lines];
    this.dirty = true;
  }

  handleKind(event) {
    this.change(event, (line, detail) => {
      line.kind = detail.value;
      line.donorContactId = null;
      line.donorAccountId = null;
    });
  }

  handleDonor(event) {
    this.change(event, (line, detail) => {
      const id = detail.recordId || null;
      if (line.kind === PERSON && !this.batch.hasPersonAccounts) {
        line.donorContactId = id;
        line.donorAccountId = null;
      } else {
        line.donorAccountId = id;
        line.donorContactId = null;
      }
    });
  }

  handleField(event) {
    const field = event.target.dataset.field;
    this.change(event, (line, detail) => {
      let value = detail.recordId !== undefined ? detail.recordId : detail.value;
      if (field === 'amount') {
        value = value === '' || value === null ? null : Number(value);
      }
      line[field] = value === '' ? null : value;
    });
  }

  handleAdd() {
    this.lines = [...this.lines, this.toLocal({ id: null })];
    this.dirty = true;
  }

  handleRemove(event) {
    const line = this.lineFor(event);
    if (line?.id) {
      this.removedIds = [...this.removedIds, line.id];
    }
    this.lines = this.lines.filter((candidate) => candidate !== line);
    this.dirty = true;
  }

  async handleSave() {
    if (await this.save()) {
      this.toast(savedToast, 'success');
    }
  }

  async save() {
    this.busy = true;
    this.formError = null;
    try {
      const view = await saveLines({
        batchId: this.recordId,
        lines: this.lines.map((line) => ({
          id: line.id,
          donorContactId: line.donorContactId,
          donorAccountId: line.donorAccountId,
          amount: line.amount,
          giftDate: line.giftDate,
          paymentMethod: line.paymentMethod,
          paymentReference: line.paymentReference,
          fundId: line.fundId,
          appealId: line.appealId
        })),
        removedLineIds: this.removedIds
      });
      this.batch = view;
      this.lines = view.lines.map((line) => this.toLocal(line));
      this.removedIds = [];
      this.dirty = false;
      return true;
    } catch (error) {
      this.formError = messageOf(error, errorSaveRows);
      return false;
    } finally {
      this.busy = false;
    }
  }

  async handlePost() {
    if (this.dirty && !(await this.save())) {
      return;
    }
    this.busy = true;
    this.lineErrors = {};
    try {
      const result = await postBatch({ batchId: this.recordId });
      if (!result.success) {
        this.formError = result.formError;
        const byLine = {};
        (result.lineErrors || []).forEach((error) => {
          byLine[error.lineId] = [...(byLine[error.lineId] || []), error.message];
        });
        this.lineErrors = byLine;
        return;
      }
      this.formError = null;
      this.toast(postedToast.replace('{0}', result.giftCount), 'success');
      await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
      await this.load();
    } catch (error) {
      this.formError = messageOf(error, errorPostFailed);
    } finally {
      this.busy = false;
    }
  }

  toast(message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title: message, variant }));
  }
}

function messageOf(error, fallback) {
  return error?.body?.message || fallback;
}
