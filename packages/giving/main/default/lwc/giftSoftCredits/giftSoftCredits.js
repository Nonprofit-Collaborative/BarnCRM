import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import SOFT_CREDIT_OBJECT from '@salesforce/schema/Soft_Credit__c';
import ROLE_FIELD from '@salesforce/schema/Soft_Credit__c.Role__c';
import getCredits from '@salesforce/apex/SoftCreditController.getCredits';
import addCredit from '@salesforce/apex/SoftCreditController.addCredit';
import removeCredit from '@salesforce/apex/SoftCreditController.removeCredit';

import TITLE from '@salesforce/label/c.Giving_SoftCredits_Title';
import EMPTY from '@salesforce/label/c.Giving_SoftCredits_Empty';
import ADD from '@salesforce/label/c.Giving_SoftCredits_Add';
import REMOVE from '@salesforce/label/c.Giving_SoftCredits_Remove';
import SAVE from '@salesforce/label/c.Giving_SoftCredits_Save';
import CANCEL from '@salesforce/label/c.Giving_SoftCredits_Cancel';
import AUTOMATIC_BADGE from '@salesforce/label/c.Giving_SoftCredits_AutomaticBadge';
import AUTOMATIC_HELP from '@salesforce/label/c.Giving_SoftCredits_AutomaticHelp';
import PERSON_LABEL from '@salesforce/label/c.Giving_SoftCredits_PersonLabel';
import ROLE_LABEL from '@salesforce/label/c.Giving_SoftCredits_RoleLabel';
import CUSTOM_ROLE_LABEL from '@salesforce/label/c.Giving_SoftCredits_CustomRoleLabel';
import AMOUNT_LABEL from '@salesforce/label/c.Giving_SoftCredits_AmountLabel';
import ACTION_FAILED from '@salesforce/label/c.Giving_SoftCredits_ActionFailed';
import { bodyMessage } from 'c/findCsv';

const ROLE_OTHER = 'Other';
const DEFAULT_ROLE = 'Solicitor';

export default class GiftSoftCredits extends LightningElement {
  @api recordId;

  labels = {
    title: TITLE,
    empty: EMPTY,
    add: ADD,
    remove: REMOVE,
    save: SAVE,
    cancel: CANCEL,
    automaticBadge: AUTOMATIC_BADGE,
    automaticHelp: AUTOMATIC_HELP,
    personLabel: PERSON_LABEL,
    roleLabel: ROLE_LABEL,
    customRoleLabel: CUSTOM_ROLE_LABEL,
    amountLabel: AMOUNT_LABEL
  };

  panel;
  wiredPanel;
  errorMessage;
  busy = false;
  showForm = false;
  draftPersonId;
  draftRole = DEFAULT_ROLE;
  draftCustomRole;
  draftAmount;

  /**
   * The role list comes from the picklist itself rather than from a list in this file, so an
   * organization that adds a role of its own sees it here, and so the words are the org's.
   */
  @wire(getObjectInfo, { objectApiName: SOFT_CREDIT_OBJECT })
  objectInfo;

  @wire(getPicklistValues, {
    recordTypeId: '$objectInfo.data.defaultRecordTypeId',
    fieldApiName: ROLE_FIELD
  })
  rolePicklist;

  get roleOptions() {
    if (this.rolePicklist && this.rolePicklist.data) {
      return this.rolePicklist.data.values.map((entry) => ({
        label: entry.label,
        value: entry.value
      }));
    }
    return [];
  }

  @wire(getCredits, { giftId: '$recordId' })
  wiredCredits(result) {
    this.wiredPanel = result;
    if (result.data) {
      this.panel = result.data;
      this.errorMessage = undefined;
    } else if (result.error) {
      this.errorMessage = bodyMessage(result.error, ACTION_FAILED);
    }
  }

  get credits() {
    const rows = this.panel && this.panel.credits ? this.panel.credits : [];
    return rows.map((credit) => ({
      ...credit,
      roleText: credit.role === ROLE_OTHER && credit.customRole ? credit.customRole : credit.role,
      showRemove: !credit.isAutomatic && this.canRemove
    }));
  }

  get hasCredits() {
    return this.credits.length > 0;
  }

  get isEmpty() {
    return !!this.panel && !this.hasCredits;
  }

  get canAdd() {
    return !!(this.panel && this.panel.canAdd);
  }

  get canRemove() {
    return !!(this.panel && this.panel.canRemove);
  }

  get addDisabled() {
    return !this.canAdd || this.busy;
  }

  get isCustomRole() {
    return this.draftRole === ROLE_OTHER;
  }

  get saveDisabled() {
    return this.busy || !this.draftPersonId;
  }

  get hasError() {
    return !!this.errorMessage;
  }

  handleShowForm() {
    this.showForm = true;
    this.errorMessage = undefined;
  }

  handleCancel() {
    this.resetForm();
  }

  handlePersonChange(event) {
    this.draftPersonId = event.detail ? event.detail.recordId : undefined;
  }

  handleRoleChange(event) {
    this.draftRole = event.detail.value;
  }

  handleCustomRoleChange(event) {
    this.draftCustomRole = event.detail.value;
  }

  handleAmountChange(event) {
    this.draftAmount = event.detail.value;
  }

  handleSave() {
    this.busy = true;
    this.errorMessage = undefined;
    return addCredit({
      giftId: this.recordId,
      personId: this.draftPersonId,
      role: this.draftRole,
      customRole: this.draftCustomRole,
      amount: this.draftAmount === undefined ? null : this.draftAmount
    })
      .then((panel) => {
        this.panel = panel;
        this.resetForm();
        return refreshApex(this.wiredPanel);
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, ACTION_FAILED);
      })
      .finally(() => {
        this.busy = false;
      });
  }

  handleRemove(event) {
    const softCreditId = event.target.dataset.credit;
    this.busy = true;
    this.errorMessage = undefined;
    return removeCredit({ softCreditId })
      .then((panel) => {
        this.panel = panel;
        return refreshApex(this.wiredPanel);
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, ACTION_FAILED);
      })
      .finally(() => {
        this.busy = false;
      });
  }

  resetForm() {
    this.showForm = false;
    this.draftPersonId = undefined;
    this.draftRole = DEFAULT_ROLE;
    this.draftCustomRole = undefined;
    this.draftAmount = undefined;
  }
}
