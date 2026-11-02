import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getProgram from '@salesforce/apex/GrantProgramController.getProgram';
import setProgram from '@salesforce/apex/GrantProgramController.setProgram';

import TITLE from '@salesforce/label/c.Core_Shared_Program';
import NONE from '@salesforce/label/c.Funders_Program_None';
import NOT_INSTALLED from '@salesforce/label/c.Funders_Program_NotInstalled';
import MISSING from '@salesforce/label/c.Funders_Program_Missing';
import SAVE from '@salesforce/label/c.Core_Kit_Save';
import SAVED from '@salesforce/label/c.Funders_Program_Saved';
import ERROR_ACTION from '@salesforce/label/c.Funders_Pipeline_ErrorUnexpected';

const NONE_VALUE = '';

const messageOf = (error) =>
  (error && error.body && error.body.message) || (error && error.message) || ERROR_ACTION;

/**
 * The Program card on a grant's page (F-01, canonical model 29ZH R-GN4): the program the grant
 * pays for, chosen from the Programs module's programs and saved by record identifier, so Funders
 * works without Programs. Without Programs it says so; a program that has gone says so too.
 */
export default class GrantProgram extends LightningElement {
  @api recordId;

  labels = { title: TITLE, notInstalled: NOT_INSTALLED, missing: MISSING, save: SAVE };

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
      this.card = await getProgram({ grantId: this.recordId });
      this.value = (this.card && this.card.programId) || NONE_VALUE;
      this.errorMessage = undefined;
    } catch (error) {
      this.card = undefined;
      this.errorMessage = messageOf(error);
    } finally {
      this.isLoading = false;
    }
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
    return (this.card && this.card.programName) || NONE;
  }

  get options() {
    const options = [{ label: NONE, value: NONE_VALUE }];
    ((this.card && this.card.options) || []).forEach((option) => options.push(option));
    return options;
  }

  get saveDisabled() {
    return this.isSaving || this.value === ((this.card && this.card.programId) || NONE_VALUE);
  }

  handleChange(event) {
    this.value = event.detail.value;
  }

  async handleSave() {
    this.isSaving = true;
    try {
      await setProgram({ grantId: this.recordId, programId: this.value || null });
      this.dispatchEvent(new ShowToastEvent({ message: SAVED, variant: 'success' }));
      await this.load();
    } catch (error) {
      this.dispatchEvent(new ShowToastEvent({ message: messageOf(error), variant: 'error' }));
    } finally {
      this.isSaving = false;
    }
  }
}
