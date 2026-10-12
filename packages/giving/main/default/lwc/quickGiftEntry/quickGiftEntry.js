import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import GIFT_OBJECT from '@salesforce/schema/Gift__c';
import FUND_OBJECT from '@salesforce/schema/Fund__c';
import APPEAL_OBJECT from '@salesforce/schema/Appeal__c';

import getDefaults from '@salesforce/apex/QuickGiftEntryController.getDefaults';
import saveGift from '@salesforce/apex/QuickGiftEntryController.saveGift';
import getPaymentChoices from '@salesforce/apex/QuickGiftEntryController.getPaymentChoices';

import heading from '@salesforce/label/c.Giving_QuickGiftEntry_Heading';
import donorKindLabel from '@salesforce/label/c.Giving_QuickGiftEntry_DonorKindLabel';
import donorKindPerson from '@salesforce/label/c.Giving_QuickGiftEntry_DonorKindPerson';
import donorKindOrganization from '@salesforce/label/c.Giving_QuickGiftEntry_DonorKindOrganization';
import personLabel from '@salesforce/label/c.Giving_QuickGiftEntry_PersonLabel';
import newPerson from '@salesforce/label/c.Giving_QuickGiftEntry_NewPerson';
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
import paysLabel from '@salesforce/label/c.Giving_GiftEntryPays_Label';
import paysHelp from '@salesforce/label/c.Giving_GiftEntryPays_Help';
import paysNone from '@salesforce/label/c.Giving_GiftEntryPays_None';
import paysOneSuggested from '@salesforce/label/c.Giving_GiftEntryPays_OneSuggested';
import paysSeveralSuggested from '@salesforce/label/c.Giving_GiftEntryPays_SeveralSuggested';
import paysErrorLoad from '@salesforce/label/c.Giving_GiftEntryPays_ErrorLoad';

const IN_KIND = 'In-kind';
/** How long typing has to pause before the donor's payments are looked up again. */
const PAYMENT_LOOKUP_DELAY_MS = 300;
const PERSON = 'person';
const ORGANIZATION = 'organization';
const ACCOUNT = 'Account';
const CONTACT = 'Contact';

/** The order the fields appear in, so the first message is the first one to fix. */
const FIELD_ORDER = [
  ['donor', 'donor-person', 'donor-organization'],
  ['amount', 'amount'],
  ['giftDate', 'gift-date'],
  ['installmentId', 'pays'],
  ['giftType', 'gift-type'],
  ['inKindDescription', 'in-kind-description'],
  ['fairMarketValue', 'fair-market-value'],
  ['appealId', 'appeal'],
  ['fundId', 'fund']
];

/**
 * Quick gift entry (G-03): one screen, built for a phone, for a gift that has just
 * arrived. Defaults come from BarnCRM Settings, validation messages come back from the
 * controller and are set on the field that caused them through the base components' own
 * validity, so each message is announced and tied to its field.
 */
export default class QuickGiftEntry extends NavigationMixin(LightningElement) {
  /** Set when the component sits on a record page, so the donor can be filled in. */
  @api recordId;
  /** The object of the record page the component sits on, when it sits on one. */
  @api objectApiName;

  labels = {
    heading,
    donorKindLabel,
    personLabel,
    newPerson,
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
    openGiftLink,
    paysLabel,
    paysHelp,
    paysErrorLoad
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
  /** The scheduled payment this gift pays; empty means None, a gift on its own (R-DM8). */
  installmentId = '';
  /** The donor's payments as the controller last described them, or null when there are none to show. */
  paymentChoices = null;
  /** True once the person chose in the list themselves, so a later lookup keeps their choice. */
  paymentPicked = false;
  paymentNote;
  paymentLoadFailed = false;
  paymentLookup = 0;
  paymentTimer;

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

  disconnectedCallback() {
    clearTimeout(this.paymentTimer);
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

  get isSaveDisabled() {
    return this.saving || this.entrySaved;
  }

  /** The list appears only for a gift of money from a donor who still owes a payment. */
  get showPayments() {
    return (
      this.isMoneyGift && Boolean(this.paymentChoices) && this.paymentChoices.choices.length > 0
    );
  }

  /** None first, always, then the donor's payments earliest due first. */
  get paymentOptions() {
    const choices = this.paymentChoices ? this.paymentChoices.choices : [];
    return [
      { label: paysNone, value: '' },
      ...choices.map((choice) => ({ label: choice.label, value: choice.value }))
    ];
  }

  handleDonorKindChange(event) {
    this.markChanged(event);
    this.donorKind = event.detail.value;
    this.donorId = undefined;
    this.forgetPayment();
  }

  handleDonorChange(event) {
    this.markChanged(event);
    this.donorId = event.detail ? event.detail.recordId : undefined;
    this.forgetPayment();
    this.schedulePaymentLookup();
  }

  handleAmountChange(event) {
    this.markChanged(event);
    this.amount = event.detail.value;
    this.schedulePaymentLookup();
  }

  handleDateChange(event) {
    this.markChanged(event);
    this.giftDate = event.detail.value;
    this.schedulePaymentLookup();
  }

  handlePaymentChange(event) {
    this.markChanged(event);
    this.installmentId = event.detail.value || '';
    this.paymentPicked = true;
    this.paymentNote = undefined;
  }

  /** A new donor owes different payments: what was chosen for the last one goes. */
  forgetPayment() {
    this.paymentLookup += 1;
    this.paymentChoices = null;
    this.installmentId = '';
    this.paymentPicked = false;
    this.paymentNote = undefined;
    this.paymentLoadFailed = false;
  }

  /** Waits for typing to pause, so a lookup is not made for every digit of an amount. */
  schedulePaymentLookup() {
    clearTimeout(this.paymentTimer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.paymentTimer = setTimeout(() => {
      this.lookUpPayments();
    }, PAYMENT_LOOKUP_DELAY_MS);
  }

  /**
   * Asks for the donor's payments still owed. Only the latest answer is used, so a slow reply
   * to an earlier amount never overwrites the list for the amount on screen.
   */
  async lookUpPayments() {
    if (!this.donorId) {
      this.forgetPayment();
      return;
    }
    const lookup = ++this.paymentLookup;
    const donor = this.donorIds();
    try {
      const choices = await getPaymentChoices({
        donorContactId: donor.contactId,
        donorAccountId: donor.accountId,
        giftDate: this.giftDate || null,
        amount: this.numberOrNull(this.amount)
      });
      if (lookup !== this.paymentLookup) {
        return;
      }
      this.paymentLoadFailed = false;
      this.applyPaymentChoices(choices);
    } catch {
      // The controller logged the cause; the gift can still be saved on its own.
      if (lookup === this.paymentLookup) {
        this.paymentChoices = null;
        this.installmentId = '';
        this.paymentNote = undefined;
        this.paymentLoadFailed = true;
      }
    }
  }

  /**
   * Never applies a payment unseen (R-DM8): a choice the person made stays while it is still
   * offered; otherwise a payment is chosen in advance only when it is the only suggestion, and
   * the note under the list says why.
   */
  applyPaymentChoices(choices) {
    const list = choices && Array.isArray(choices.choices) ? choices.choices : [];
    this.paymentChoices = { ...choices, choices: list };
    const offered = list.some((choice) => choice.value === this.installmentId);
    if (this.paymentPicked && (this.installmentId === '' || offered)) {
      return;
    }
    this.paymentPicked = false;
    if (choices && choices.suggestedId) {
      this.installmentId = choices.suggestedId;
      this.paymentNote = paysOneSuggested;
    } else {
      this.installmentId = '';
      const several = choices && choices.suggestedCount > 1;
      this.paymentNote = several
        ? paysSeveralSuggested.replace('{0}', choices.suggestedCount)
        : undefined;
    }
  }

  /**
   * Switching between money and goods clears what belongs to the other kind, so a value typed
   * before the type was chosen is never saved against a gift it does not belong to.
   */
  handleTypeChange(event) {
    this.markChanged(event);
    this.giftType = event.detail.value;
    if (this.isInKindGift) {
      this.amount = undefined;
    } else {
      this.inKindDescription = undefined;
      this.fairMarketValue = undefined;
    }
    this.schedulePaymentLookup();
  }

  handleInKindDescriptionChange(event) {
    this.markChanged(event);
    this.inKindDescription = event.detail.value;
  }

  handleFairMarketValueChange(event) {
    this.markChanged(event);
    this.fairMarketValue = event.detail.value;
  }

  handlePaymentReferenceChange(event) {
    this.markChanged(event);
    this.paymentReference = event.detail.value;
  }

  handleAppealChange(event) {
    this.markChanged(event);
    this.appealId = event.detail ? event.detail.recordId : undefined;
  }

  handleFundChange(event) {
    this.markChanged(event);
    this.fundId = event.detail ? event.detail.recordId : undefined;
  }

  /**
   * Any edit makes this a gift that has not been saved yet, and takes away the controller's
   * message from the field being edited: the person is fixing it.
   */
  markChanged(event) {
    this.entrySaved = false;
    const target = event && event.target;
    const entry =
      target && FIELD_ORDER.find((candidate) => candidate.slice(1).includes(target.dataset.id));
    if (entry && this.fieldErrors[entry[0]]) {
      const remaining = { ...this.fieldErrors };
      delete remaining[entry[0]];
      this.setFieldErrors(remaining);
    }
  }

  /** New person: the standard new record form, so the person is created the usual way. */
  handleNewPerson() {
    this[NavigationMixin.Navigate]({
      type: 'standard__objectPage',
      attributes: { objectApiName: this.personObjectApiName, actionName: 'new' },
      // Stay on this form after the save rather than opening the new record, so the
      // person can be picked straight away and nothing typed so far is lost.
      state: { navigationLocation: 'RELATED_LIST', useRecordTypeCheck: 1 }
    });
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
    if (this.donorId) {
      this.schedulePaymentLookup();
    }
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
    this.setFieldErrors({});
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

  /** Where people are accounts, a person donor is an account; otherwise a contact. */
  donorIds() {
    const ids = { contactId: null, accountId: null };
    if (this.donorId) {
      if (this.isPersonDonor && !this.hasPersonAccounts) {
        ids.contactId = this.donorId;
      } else {
        ids.accountId = this.donorId;
      }
    }
    return ids;
  }

  buildInput() {
    const donor = this.donorIds();
    return {
      donorContactId: donor.contactId,
      donorAccountId: donor.accountId,
      amount: this.amountAsNumber(),
      giftDate: this.giftDate || null,
      giftType: this.giftType || null,
      appealId: this.appealId || null,
      fundId: this.fundId || null,
      paymentReference: this.paymentReference || null,
      inKindDescription: this.isInKindGift ? this.inKindDescription || null : null,
      fairMarketValue: this.isInKindGift ? this.numberOrNull(this.fairMarketValue) : null,
      installmentId: this.isMoneyGift && this.installmentId ? this.installmentId : null
    };
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
    this.setFieldErrors(errors);
    this.formError = result && result.formError ? result.formError : undefined;
    if (!this.formError && fieldErrors.length === 0) {
      this.formError = errorUnexpected;
    }
  }

  /**
   * Puts each message on its own field with the base components' custom validity, which
   * shows it under the field, links it to the field and announces it. A field that had a
   * message and no longer does is cleared the same way.
   */
  setFieldErrors(errors) {
    FIELD_ORDER.forEach(([key, ...dataIds]) => {
      const message = errors[key] || '';
      const hadMessage = Boolean(this.fieldErrors[key]);
      dataIds.forEach((dataId) => {
        const field = this.template.querySelector(`[data-id="${dataId}"]`);
        if (!field || typeof field.setCustomValidity !== 'function') {
          return;
        }
        field.setCustomValidity(message);
        if (message || hadMessage) {
          field.reportValidity();
        }
      });
    });
    this.fieldErrors = errors;
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
    this.forgetPayment();
    if (this.donorId) {
      this.schedulePaymentLookup();
    }
    this.setFieldErrors({});
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
