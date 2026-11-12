import { LightningElement, api, wire } from 'lwc';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import ALLOCATION_OBJECT from '@salesforce/schema/Gift_Allocation__c';
import getState from '@salesforce/apex/GiftAllocationController.getState';
import save from '@salesforce/apex/GiftAllocationController.save';

import EDIT_FUNDS from '@salesforce/label/c.Giving_FundSplit_EditFunds';
import SAVE from '@salesforce/label/c.Core_Kit_Save';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import { bodyMessage } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { iconFor } from 'c/barnIcons';

/**
 * The Gift Allocations card on a gift's page (people-giving-16): the funds the gift went to,
 * and Edit Funds, which opens the fund split editor and saves the whole split at once. A gift
 * in the books (posted, or dated in a closed period) shows why its funds cannot change, in the
 * lock's own words, instead of the button.
 */
export default class GiftAllocations extends LightningElement {
  helpReady = isHelpLoaded('Giving');

  @api recordId;

  labels = { editFunds: EDIT_FUNDS, save: SAVE, cancel: CANCEL };
  icons = { allocation: iconFor('Gift_Allocation__c') };

  state;
  editing = false;
  draft = [];
  draftValid = false;
  busy = false;
  errorMessage;
  savedMessage;

  @wire(getObjectInfo, { objectApiName: ALLOCATION_OBJECT })
  allocationInfo;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Giving').then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  async load() {
    try {
      this.state = await getState({ giftId: this.recordId });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = bodyMessage(error, helpText('Giving', 'Giving_Gift_UnexpectedError'));
    }
  }

  fieldLabel(apiName, fallback) {
    const info = this.allocationInfo && this.allocationInfo.data;
    const field = info && info.fields && info.fields[apiName];
    return field ? field.label : fallback;
  }

  get title() {
    const info = this.allocationInfo && this.allocationInfo.data;
    return info ? info.labelPlural : '';
  }

  get columns() {
    return {
      fund: this.fieldLabel('Fund__c', 'Fund'),
      amount: this.fieldLabel('Amount__c', 'Amount'),
      percent: this.fieldLabel('Percent__c', 'Percent')
    };
  }

  get rows() {
    return this.state && this.state.rows
      ? this.state.rows.map((row) => ({
          ...row,
          share: row.percent === null || row.percent === undefined ? null : row.percent / 100
        }))
      : [];
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get showEmpty() {
    return !!this.state && !this.hasRows && !this.editing;
  }

  get noneText() {
    return helpText('Giving', 'Giving_GiftAllocations_None');
  }

  get showEditButton() {
    return !!(this.state && this.state.canEdit) && !this.editing;
  }

  get lockedMessage() {
    return this.state ? this.state.lockedMessage : undefined;
  }

  get showList() {
    return this.hasRows && !this.editing;
  }

  get giftAmount() {
    return this.state ? this.state.giftAmount : 0;
  }

  get saveDisabled() {
    return this.busy || !this.draftValid;
  }

  handleEdit() {
    this.draft = this.rows.map((row) => ({
      fundId: row.fundId,
      fundName: row.fundName,
      amount: row.amount
    }));
    this.draftValid = false;
    this.errorMessage = undefined;
    this.savedMessage = undefined;
    this.editing = true;
  }

  handleSplitChange(event) {
    this.draft = event.detail.allocations;
    this.draftValid = event.detail.valid;
  }

  handleCancel() {
    this.editing = false;
    this.errorMessage = undefined;
  }

  async handleSave() {
    this.busy = true;
    this.errorMessage = undefined;
    try {
      this.state = await save({
        giftId: this.recordId,
        allocations: this.draft.map((row) => ({ fundId: row.fundId, amount: row.amount }))
      });
      this.editing = false;
      this.savedMessage = helpText('Giving', 'Giving_GiftAllocations_Saved');
      // The gift's other lists and the fund totals on the page read the new split.
      notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
    } catch (error) {
      this.errorMessage = bodyMessage(error, helpText('Giving', 'Giving_Gift_UnexpectedError'));
    } finally {
      this.busy = false;
    }
  }
}
