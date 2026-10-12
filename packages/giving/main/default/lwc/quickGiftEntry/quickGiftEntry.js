import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import GIFT_OBJECT from '@salesforce/schema/Gift__c';
import FUND_OBJECT from '@salesforce/schema/Fund__c';
import APPEAL_OBJECT from '@salesforce/schema/Appeal__c';

import getDefaults from '@salesforce/apex/QuickGiftEntryController.getDefaults';
import saveGift from '@salesforce/apex/QuickGiftEntryController.saveGift';

import heading from '@salesforce/label/c.Giving_QuickGiftEntry_Heading';
import donorKindLabel from '@salesforce/label/c.Giving_QuickGiftEntry_DonorKindLabel';
import donorKindPerson from '@salesforce/label/c.Giving_QuickGiftEntry_DonorKindPerson';
import donorKindOrganization from '@salesforce/label/c.Giving_QuickGiftEntry_DonorKindOrganization';
import personLabel from '@salesforce/label/c.Giving_QuickGiftEntry_PersonLabel';
import organizationLabel from '@salesforce/label/c.Giving_QuickGiftEntry_OrganizationLabel';
import donorPlaceholder from '@salesforce/label/c.Giving_QuickGiftEntry_DonorPlaceholder';
import amountLabel from '@salesforce/label/c.Giving_QuickGiftEntry_AmountLabel';
import dateLabel from '@salesforce/label/c.Giving_QuickGiftEntry_DateLabel';
import typeLabel from '@salesforce/label/c.Giving_QuickGiftEntry_TypeLabel';
import typePlaceholder from '@salesforce/label/c.Giving_QuickGiftEntry_TypePlaceholder';
import appealLabel from '@salesforce/label/c.Giving_QuickGiftEntry_AppealLabel';
import fundLabel from '@salesforce/label/c.Giving_QuickGiftEntry_FundLabel';
import paymentReferenceLabel from '@salesforce/label/c.Giving_QuickGiftEntry_PaymentReferenceLabel';
import inKindDescriptionLabel from '@salesforce/label/c.Giving_QuickGiftEntry_InKindDescriptionLabel';
import inKindDescriptionHelp from '@salesforce/label/c.Giving_QuickGiftEntry_InKindDescriptionHelp';
import fairMarketValueLabel from '@salesforce/label/c.Giving_QuickGiftEntry_FairMarketValueLabel';
import fairMarketValueHelp from '@salesforce/label/c.Giving_QuickGiftEntry_FairMarketValueHelp';
import saveButton from '@salesforce/label/c.Giving_QuickGiftEntry_SaveButton';
import saveAndNewButton from '@salesforce/label/c.Giving_QuickGiftEntry_SaveAndNewButton';
import savingMessage from '@salesforce/label/c.Giving_QuickGiftEntry_SavingMessage';
import successTitle from '@salesforce/label/c.Giving_QuickGiftEntry_SuccessTitle';
import successMessage from '@salesforce/label/c.Giving_QuickGiftEntry_SuccessMessage';
import openGiftLink from '@salesforce/label/c.Giving_QuickGiftEntry_OpenGiftLink';
import errorTitle from '@salesforce/label/c.Giving_QuickGiftEntry_ErrorTitle';
import errorLoadDefaults from '@salesforce/label/c.Giving_QuickGiftEntry_ErrorLoadDefaults';
import errorUnexpected from '@salesforce/label/c.Giving_QuickGiftEntry_ErrorUnexpected';
import fundNotApplied from '@salesforce/label/c.Giving_QuickGiftEntry_FundNotApplied';

const IN_KIND = 'In-kind';
const PERSON = 'person';
const ORGANIZATION = 'organization';
const ACCOUNT = 'Account';
const CONTACT = 'Contact';

/** The order the fields appear in, so the first message is the first one to fix. */
const FIELD_ORDER = [
  ['donor', 'donor-person', 'donor-organization'],
  ['amount', 'amount'],
  ['giftDate', 'gift-date'],
  ['giftType', 'gift-type'],
  ['inKindDescription', 'in-kind-description'],
  ['fairMarketValue', 'fair-market-value'],
  ['appealId', 'appeal'],
  ['fundId', 'fund']
];

/**
 * Quick gift entry (G-03): one screen, built for a phone, for a gift that has just
 * arrived. Defaults come from BarnCRM Settings, validation messages come back from the
 * controller and are shown beside the field that caused them.
 */
export default class QuickGiftEntry extends LightningElement {
  /** Set when the component sits on a record page, so the donor can be filled in. */
  @api recordId;
  /** The object of the record page the component sits on, when it sits on one. */
  @api objectApiName;

  labels = {
    heading,
    donorKindLabel,
    personLabel,
    organizationLabel,
    donorPlaceholder,
    amountLabel,
    dateLabel,
    typeLabel,
    typePlaceholder,
    appealLabel,
    fundLabel,
    paymentReferenceLabel,
    inKindDescriptionLabel,
    inKindDescriptionHelp,
    fairMarketValueLabel,
    fairMarketValueHelp,
    saveButton,
    saveAndNewButton,
    savingMessage,
    errorTitle,
    openGiftLink
  };

  donorKind = PERSON;
  donorId;
  amount;
  giftDate;
  giftType;
  inKindDescription;
  fairMarketValue;
  appealId;
  fundId;
  paymentReference;

  giftTypeOptions = [];
  hasPersonAccounts = false;
  fieldErrors = {};
  formError;
  saving = false;
  savedGift;
  saveWarning;
  /**
   * True from a successful save until the person changes something or starts another
   * gift. It is what stops a second tap on Save, or a retry on a slow connection, from
   * entering the same gift twice.
   */
  entrySaved = false;

  defaults;
  prefilledDonorId;
  prefilledDonorKind;

  connectedCallback() {
    this.prefillFromRecordPage();
    this.loadDefaults();
  }

  get donorKindOptions() {
    return [
      { label: donorKindPerson, value: PERSON },
      { label: donorKindOrganization, value: ORGANIZATION }
    ];
  }

  get isPersonDonor() {
    return this.donorKind === PERSON;
  }

  /**
   * A gift is money or goods, never both (ADR-0030). Choosing In-kind takes the amount box
   * away rather than leaving it there to be filled in: an in-kind gift has no amount, and a
   * box a person can type into is a box they will type into.
   */
  get isInKindGift() {
    return this.giftType === IN_KIND;
  }

  get isMoneyGift() {
    return !this.isInKindGift;
  }

  /** Where people are accounts, the person picker searches accounts too. */
  get personObjectApiName() {
    return this.hasPersonAccounts ? ACCOUNT : CONTACT;
  }

  get accountObjectApiName() {
    return ACCOUNT;
  }

  get fundObjectApiName() {
    return FUND_OBJECT.objectApiName;
  }

  get appealObjectApiName() {
    return APPEAL_OBJECT.objectApiName;
  }

  get savedMessage() {
    return this.savedGift ? successMessage.replace('{0}', this.savedGift.name) : '';
  }

  get errorDonor() {
    return this.fieldErrors.donor;
  }

  get errorAmount() {
    return this.fieldErrors.amount;
  }

  get errorDate() {
    return this.fieldErrors.giftDate;
  }

  get errorType() {
    return this.fieldErrors.giftType;
  }

  get errorInKindDescription() {
    return this.fieldErrors.inKindDescription;
  }

  get errorFairMarketValue() {
    return this.fieldErrors.fairMarketValue;
  }

  get errorAppeal() {
    return this.fieldErrors.appealId;
  }

  get errorFund() {
    return this.fieldErrors.fundId;
  }

  get isSaveDisabled() {
    return this.saving || this.entrySaved;
  }

  handleDonorKindChange(event) {
    this.markChanged();
    this.donorKind = event.detail.value;
    this.donorId = undefined;
  }

  handleDonorChange(event) {
    this.markChanged();
    this.donorId = event.detail ? event.detail.recordId : undefined;
  }

  handleAmountChange(event) {
    this.markChanged();
    this.amount = event.detail.value;
  }

  handleDateChange(event) {
    this.markChanged();
    this.giftDate = event.detail.value;
  }

  /**
   * Switching between money and goods clears what belongs to the other kind, so a value typed
   * before the type was chosen is never saved against a gift it does not belong to.
   */
  handleTypeChange(event) {
    this.markChanged();
    this.giftType = event.detail.value;
    if (this.isInKindGift) {
      this.amount = undefined;
    } else {
      this.inKindDescription = undefined;
      this.fairMarketValue = undefined;
    }
  }

  handleInKindDescriptionChange(event) {
    this.markChanged();
    this.inKindDescription = event.detail.value;
  }

  handleFairMarketValueChange(event) {
    this.markChanged();
    this.fairMarketValue = event.detail.value;
  }

  handlePaymentReferenceChange(event) {
    this.markChanged();
    this.paymentReference = event.detail.value;
  }

  handleAppealChange(event) {
    this.markChanged();
    this.appealId = event.detail ? event.detail.recordId : undefined;
  }

  handleFundChange(event) {
    this.markChanged();
    this.fundId = event.detail ? event.detail.recordId : undefined;
  }

  /** Any edit makes this a gift that has not been saved yet. */
  markChanged() {
    this.entrySaved = false;
  }

  handleSave() {
    this.save(false);
  }

  handleSaveAndNew() {
    this.save(true);
  }

  async loadDefaults() {
    try {
      const defaults = await getDefaults();
      this.defaults = defaults || {};
      this.hasPersonAccounts = this.defaults.hasPersonAccounts === true;
      this.giftTypeOptions = (this.defaults.giftTypes || []).map((option) => ({
        label: option.label,
        value: option.value
      }));
      this.applyDefaults();
    } catch (error) {
      this.formError = this.messageFrom(error, errorLoadDefaults);
    }
  }

  applyDefaults() {
    if (!this.defaults) {
      return;
    }
    this.giftDate = this.defaults.giftDate;
    this.appealId = this.defaults.defaultAppealId;
    this.fundId = this.defaults.defaultFundId;
  }

  /**
   * On a person's or a household's page the donor is the record the person is looking
   * at, so the form starts with it filled in.
   */
  prefillFromRecordPage() {
    if (!this.recordId || !this.objectApiName) {
      return;
    }
    if (this.objectApiName === CONTACT) {
      this.prefilledDonorKind = PERSON;
    } else if (this.objectApiName === ACCOUNT) {
      this.prefilledDonorKind = ORGANIZATION;
    } else {
      return;
    }
    this.prefilledDonorId = this.recordId;
    this.donorKind = this.prefilledDonorKind;
    this.donorId = this.recordId;
  }

  async save(startAnother) {
    if (this.isSaveDisabled) {
      return;
    }
    this.formError = undefined;
    this.saveWarning = undefined;
    this.fieldErrors = {};
    this.saving = true;
    try {
      const result = await saveGift({ input: this.buildInput() });
      if (!result || result.success !== true) {
        this.applyResultErrors(result);
        this.focusFirstError();
        return;
      }
      this.entrySaved = true;
      this.saveWarning = result.fundNotApplied === true ? fundNotApplied : undefined;
      this.savedGift = {
        id: result.giftId,
        name: result.giftName,
        url: `/lightning/r/${GIFT_OBJECT.objectApiName}/${result.giftId}/view`
      };
      this.dispatchEvent(
        new ShowToastEvent({
          title: successTitle,
          message: successMessage,
          messageData: [{ url: this.savedGift.url, label: result.giftName }],
          variant: 'success'
        })
      );
      if (startAnother) {
        this.startAnotherGift();
      }
    } catch (error) {
      this.formError = this.messageFrom(error, errorUnexpected);
    } finally {
      this.saving = false;
    }
  }

  buildInput() {
    const input = {
      donorContactId: null,
      donorAccountId: null,
      amount: this.amountAsNumber(),
      giftDate: this.giftDate || null,
      giftType: this.giftType || null,
      appealId: this.appealId || null,
      fundId: this.fundId || null,
      paymentReference: this.paymentReference || null,
      inKindDescription: this.isInKindGift ? this.inKindDescription || null : null,
      fairMarketValue: this.isInKindGift ? this.numberOrNull(this.fairMarketValue) : null
    };
    if (this.donorId) {
      if (this.isPersonDonor && !this.hasPersonAccounts) {
        input.donorContactId = this.donorId;
      } else {
        input.donorAccountId = this.donorId;
      }
    }
    return input;
  }

  amountAsNumber() {
    if (this.isInKindGift) {
      return 0;
    }
    return this.numberOrNull(this.amount);
  }

  numberOrNull(value) {
    if (value === undefined || value === null || value === '') {
      return null;
    }
    const parsed = Number(value);
    return Number.isNaN(parsed) ? null : parsed;
  }

  applyResultErrors(result) {
    const errors = {};
    const fieldErrors = result && result.fieldErrors ? result.fieldErrors : [];
    fieldErrors.forEach((fieldError) => {
      errors[fieldError.field] = fieldError.message;
    });
    this.fieldErrors = errors;
    this.formError = result && result.formError ? result.formError : undefined;
    if (!this.formError && fieldErrors.length === 0) {
      this.formError = errorUnexpected;
    }
  }

  /**
   * Moves the keyboard to the first field the controller complained about, so a person
   * working without a mouse lands on the thing to fix rather than hunting for it.
   */
  focusFirstError() {
    const first = FIELD_ORDER.find((entry) => this.fieldErrors[entry[0]]);
    if (!first) {
      return;
    }
    for (const dataId of first.slice(1)) {
      const target = this.template.querySelector(`[data-id="${dataId}"]`);
      if (target && typeof target.focus === 'function') {
        target.focus();
        return;
      }
    }
  }

  /** Keeps the date, the appeal and the fund, clears what changes gift to gift. */
  startAnotherGift() {
    this.entrySaved = false;
    this.donorId = this.prefilledDonorId;
    this.donorKind = this.prefilledDonorKind || PERSON;
    this.amount = undefined;
    this.giftType = undefined;
    this.inKindDescription = undefined;
    this.fairMarketValue = undefined;
    this.paymentReference = undefined;
    this.fieldErrors = {};
    const donor = this.template.querySelector('[data-id="donor-person"]')
      ? this.template.querySelector('[data-id="donor-person"]')
      : this.template.querySelector('[data-id="donor-organization"]');
    if (donor && typeof donor.focus === 'function') {
      donor.focus();
    }
  }

  messageFrom(error, fallback) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    if (error && error.message) {
      return error.message;
    }
    return fallback;
  }
}
