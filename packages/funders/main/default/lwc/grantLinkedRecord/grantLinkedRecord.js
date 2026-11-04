import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { messageFrom } from 'c/findCsv';
import getProgram from '@salesforce/apex/GrantProgramController.getProgram';
import setProgram from '@salesforce/apex/GrantProgramController.setProgram';
import getFund from '@salesforce/apex/GrantFundController.getFund';
import setFund from '@salesforce/apex/GrantFundController.setFund';

import PROGRAM_TITLE from '@salesforce/label/c.Core_Shared_Program';
import PROGRAM_NONE from '@salesforce/label/c.Funders_Program_None';
import PROGRAM_NOT_INSTALLED from '@salesforce/label/c.Funders_Program_NotInstalled';
import PROGRAM_MISSING from '@salesforce/label/c.Funders_Program_Missing';
import PROGRAM_SAVED from '@salesforce/label/c.Funders_Program_Saved';
import FUND_NONE from '@salesforce/label/c.Funders_Fund_None';
import FUND_NOT_INSTALLED from '@salesforce/label/c.Funders_Fund_NotInstalled';
import FUND_MISSING from '@salesforce/label/c.Funders_Fund_Missing';
import FUND_SAVED from '@salesforce/label/c.Core_Shared_Saved';
import SAVE from '@salesforce/label/c.Core_Kit_Save';
import ERROR_ACTION from '@salesforce/label/c.Funders_Pipeline_ErrorUnexpected';

const NONE_VALUE = '';

const messageOf = (error) => messageFrom(error, ERROR_ACTION);

/**
 * What each kind of linked record differs in. Program (F-01, canonical model 29ZH R-GN4): the
 * program the grant pays for, from the Programs module. Fund (F-03, 29ZH R-GN8): the Giving fund
 * the grant's money is booked to, from Giving's active funds; its title is the Giving Fund
 * field's label, read by describe.
 */
const KINDS = {
  Program: {
    icon: 'custom:custom8',
    dataId: 'program',
    title: () => PROGRAM_TITLE,
    load: (grantId) => getProgram({ grantId }),
    save: (grantId, id) => setProgram({ grantId, programId: id }),
    idOf: (card) => card.programId,
    nameOf: (card) => card.programName,
    labels: {
      none: PROGRAM_NONE,
      notInstalled: PROGRAM_NOT_INSTALLED,
      missing: PROGRAM_MISSING,
      saved: PROGRAM_SAVED
    }
  },
  Fund: {
    icon: 'custom:custom17',
    dataId: 'fund',
    title: (card) => (card && card.title) || '',
    load: (grantId) => getFund({ grantId }),
    save: (grantId, id) => setFund({ grantId, fundId: id }),
    idOf: (card) => card.fundId,
    nameOf: (card) => card.fundName,
    labels: {
      none: FUND_NONE,
      notInstalled: FUND_NOT_INSTALLED,
      missing: FUND_MISSING,
      saved: FUND_SAVED
    }
  }
};

/**
 * A linked-record card on a grant's page: the program or the Giving fund a grant names, chosen
 * from the other module's records and saved by record identifier, so Funders works without
 * Programs or Giving. Without the module it says so; a record that has gone says so too.
 */
export default class GrantLinkedRecord extends LightningElement {
  @api recordId;
  /** Program or Fund, set on the record page. */
  @api kind = 'Program';

  saveLabel = SAVE;
  card;
  value = NONE_VALUE;
  errorMessage;
  isLoading = true;
  isSaving = false;

  get config() {
    return KINDS[this.kind] || KINDS.Program;
  }

  get labels() {
    return this.config.labels;
  }

  get title() {
    return this.config.title(this.card);
  }

  get iconName() {
    return this.config.icon;
  }

  get dataId() {
    return this.config.dataId;
  }

  get savedId() {
    return (this.card && this.config.idOf(this.card)) || NONE_VALUE;
  }

  connectedCallback() {
    this.load();
  }

  async load() {
    this.isLoading = true;
    try {
      this.card = await this.config.load(this.recordId);
      this.value = this.savedId;
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
    return (this.card && this.config.nameOf(this.card)) || this.labels.none;
  }

  get options() {
    const options = [{ label: this.labels.none, value: NONE_VALUE }];
    ((this.card && this.card.options) || []).forEach((option) => options.push(option));
    return options;
  }

  get saveDisabled() {
    return this.isSaving || this.value === this.savedId;
  }

  handleChange(event) {
    this.value = event.detail.value;
  }

  async handleSave() {
    this.isSaving = true;
    try {
      await this.config.save(this.recordId, this.value || null);
      this.dispatchEvent(new ShowToastEvent({ message: this.labels.saved, variant: 'success' }));
      await this.load();
    } catch (error) {
      this.dispatchEvent(new ShowToastEvent({ message: messageOf(error), variant: 'error' }));
    } finally {
      this.isSaving = false;
    }
  }
}
