import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getFund from '@salesforce/apex/GrantFundController.getFund';
import setFund from '@salesforce/apex/GrantFundController.setFund';

import NONE from '@salesforce/label/c.Funders_Fund_None';
import NOT_INSTALLED from '@salesforce/label/c.Funders_Fund_NotInstalled';
import MISSING from '@salesforce/label/c.Funders_Fund_Missing';
import SAVE from '@salesforce/label/c.Funders_Program_Save';
import SAVED from '@salesforce/label/c.Funders_Schedule_Saved';
import ERROR_ACTION from '@salesforce/label/c.Funders_Pipeline_ErrorUnexpected';

const NONE_VALUE = '';

const messageOf = (error) =>
  (error && error.body && error.body.message) || (error && error.message) || ERROR_ACTION;

/**
 * The Giving Fund card on a grant's page (F-03, canonical model 29ZH R-GN8): the Giving fund the
 * grant's money is booked to, chosen from Giving's active funds and saved by record identifier,
 * so Funders works without Giving. Without Giving it says so; a fund that has gone says so too.
 * The title is the Giving Fund field's label, read by describe.
 */
export default class GrantFund extends LightningElement {
  @api recordId;

  labels = { notInstalled: NOT_INSTALLED, missing: MISSING, save: SAVE };

  card;
  value = NONE_VALUE;
  errorMessage;
  isLoading = true;
  isSaving = false;

  connectedCallback() {
    this.load();
  }

  async load() {
    this.isLoading = true;
    try {
      this.card = await getFund({ grantId: this.recordId });
      this.value = (this.card && this.card.fundId) || NONE_VALUE;
      this.errorMessage = undefined;
    } catch (error) {
      this.card = undefined;
      this.errorMessage = messageOf(error);
    } finally {
      this.isLoading = false;
    }
  }

  get title() {
    return (this.card && this.card.title) || '';
  }

  get notInstalled() {
    return Boolean(this.card) && !this.card.available;
  }

  get isMissing() {
    return Boolean(this.card && this.card.available && this.card.missing);
  }

  get canEdit() {
    return Boolean(this.card && this.card.available && this.card.canEdit);
  }

  get showReadOnly() {
    return Boolean(this.card && this.card.available && !this.card.canEdit);
  }

  get readOnlyName() {
    return (this.card && this.card.fundName) || NONE;
  }

  get options() {
    const options = [{ label: NONE, value: NONE_VALUE }];
    ((this.card && this.card.options) || []).forEach((option) => options.push(option));
    return options;
  }

  get saveDisabled() {
    return this.isSaving || this.value === ((this.card && this.card.fundId) || NONE_VALUE);
  }

  handleChange(event) {
    this.value = event.detail.value;
  }

  async handleSave() {
    this.isSaving = true;
    try {
      await setFund({ grantId: this.recordId, fundId: this.value || null });
      this.dispatchEvent(new ShowToastEvent({ message: SAVED, variant: 'success' }));
      await this.load();
    } catch (error) {
      this.dispatchEvent(new ShowToastEvent({ message: messageOf(error), variant: 'error' }));
    } finally {
      this.isSaving = false;
    }
  }
}
