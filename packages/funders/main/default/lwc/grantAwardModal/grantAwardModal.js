import LightningModal from 'lightning/modal';
import { api, wire } from 'lwc';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import recordAward from '@salesforce/apex/GrantPipelineController.recordAward';
import { messageFrom } from 'c/findCsv';
import { helpText } from 'c/barnHelpText';

import AWARD_AMOUNT from '@salesforce/label/c.Funders_Pipeline_AwardAmount';
import SAVE from '@salesforce/label/c.Core_Kit_Save';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';

const GRANT_OBJECT = 'Grant__c';

const blankToNull = (value) => (value === '' || value === undefined ? null : value);

/**
 * Record the Award (modules-16, vis-modules-11): a platform modal that moves a grant to Awarded
 * with what the award letter says, each optional: the amount awarded (filled in with the amount
 * requested), the award period and Restricted. It saves through GrantPipelineController and stays
 * open with the reason when the save is refused. It resolves `{ saved: true }` once saved, and
 * undefined when closed without saving.
 *
 * Open it with GrantAwardModal.open({ label, grant: { id, amountRequested, awardStartDate,
 * awardEndDate, restricted }, size: 'small' }).
 */
export default class GrantAwardModal extends LightningModal {
  /** The board card being awarded. */
  @api grant;

  labels = { amount: AWARD_AMOUNT, save: SAVE, cancel: CANCEL };

  amount;
  startDate;
  endDate;
  restricted = false;
  fieldLabels = {};
  errorMessage;
  isSaving = false;
  started = false;

  /** The date and Restricted labels as the org names the fields. */
  @wire(getObjectInfo, { objectApiName: GRANT_OBJECT })
  wiredInfo({ data }) {
    const fields = (data && data.fields) || {};
    const labelOf = (name) => (fields[name] && fields[name].label) || '';
    this.fieldLabels = {
      start: labelOf('Award_Start_Date__c'),
      end: labelOf('Award_End_Date__c'),
      restricted: labelOf('Restricted__c')
    };
  }

  connectedCallback() {
    if (this.started) {
      return;
    }
    this.started = true;
    const grant = this.grant || {};
    this.amount = grant.amountRequested;
    this.startDate = grant.awardStartDate;
    this.endDate = grant.awardEndDate;
    this.restricted = Boolean(grant.restricted);
  }

  handleAmount(event) {
    this.amount = event.detail.value;
  }

  handleStart(event) {
    this.startDate = event.detail.value;
  }

  handleEnd(event) {
    this.endDate = event.detail.value;
  }

  handleRestricted(event) {
    this.restricted = event.detail.checked;
  }

  handleCancel() {
    this.close();
  }

  async handleSave() {
    const inputs = [...this.template.querySelectorAll('lightning-input')];
    const valid = inputs.every(
      (input) => typeof input.reportValidity !== 'function' || input.reportValidity() !== false
    );
    if (!valid) {
      return;
    }
    this.isSaving = true;
    this.errorMessage = undefined;
    const amount = blankToNull(this.amount);
    try {
      await recordAward({
        grantId: this.grant.id,
        amountAwarded: amount === null ? null : Number(amount),
        startDate: blankToNull(this.startDate),
        endDate: blankToNull(this.endDate),
        restricted: this.restricted
      });
      this.close({ saved: true });
    } catch (error) {
      this.errorMessage = messageFrom(error, helpText('Funders', 'Funders_Shared_NotSaved'));
    } finally {
      this.isSaving = false;
    }
  }
}
