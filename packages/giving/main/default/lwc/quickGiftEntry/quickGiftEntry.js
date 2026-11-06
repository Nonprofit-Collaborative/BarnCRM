import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import Toast from 'lightning/toast';
import LOCALE from '@salesforce/i18n/locale';
import CURRENCY from '@salesforce/i18n/currency';

import GIFT_OBJECT from '@salesforce/schema/Gift__c';
import FUND_OBJECT from '@salesforce/schema/Fund__c';
import APPEAL_OBJECT from '@salesforce/schema/Appeal__c';

import getDefaults from '@salesforce/apex/QuickGiftEntryController.getDefaults';
import getDonorKind from '@salesforce/apex/QuickGiftEntryController.getDonorKind';
import getMatchableGifts from '@salesforce/apex/QuickGiftEntryController.getMatchableGifts';
import saveGift from '@salesforce/apex/QuickGiftEntryController.saveGift';
import getPaymentChoices from '@salesforce/apex/QuickGiftEntryController.getPaymentChoices';

import heading from '@salesforce/label/c.Giving_QuickGiftEntry_Heading';
import donorKindLabel from '@salesforce/label/c.Giving_QuickGiftEntry_DonorKindLabel';
import donorKindPerson from '@salesforce/label/c.Core_Section_Person';
import donorKindOrganization from '@salesforce/label/c.Core_Settings_NavGroup_Organization';
import personLabel from '@salesforce/label/c.Giving_GiftBatch_ColumnDonor';
import newPerson from '@salesforce/label/c.Giving_QuickGiftEntry_NewPerson';
import organizationLabel from '@salesforce/label/c.Core_Settings_NavGroup_Organization';
import donorPlaceholder from '@salesforce/label/c.Core_HouseholdPanel_AddExistingPlaceholder';
import amountLabel from '@salesforce/label/c.Giving_AskPipeline_FieldAmount';
import dateLabel from '@salesforce/label/c.Giving_QuickGiftEntry_DateLabel';
import typeLabel from '@salesforce/label/c.Giving_QuickGiftEntry_TypeLabel';
import typePlaceholder from '@salesforce/label/c.Giving_QuickGiftEntry_TypePlaceholder';
import appealLabel from '@salesforce/label/c.Giving_QuickGiftEntry_AppealLabel';
import fundLabel from '@salesforce/label/c.Giving_GiftBatch_ColumnFund';
import paymentReferenceLabel from '@salesforce/label/c.Giving_QuickGiftEntry_PaymentReferenceLabel';
import inKindDescriptionLabel from '@salesforce/label/c.Giving_QuickGiftEntry_InKindDescriptionLabel';
import fairMarketValueLabel from '@salesforce/label/c.Giving_QuickGiftEntry_FairMarketValueLabel';
import saveButton from '@salesforce/label/c.Core_Kit_Save';
import saveAndNewButton from '@salesforce/label/c.Giving_QuickGiftEntry_SaveAndNewButton';
import savingMessage from '@salesforce/label/c.Giving_QuickGiftEntry_SavingMessage';
import successTitle from '@salesforce/label/c.Giving_QuickGiftEntry_SuccessTitle';
import successMessage from '@salesforce/label/c.Giving_QuickGiftEntry_SuccessMessage';
import openGiftLink from '@salesforce/label/c.Giving_QuickGiftEntry_OpenGiftLink';
import errorTitle from '@salesforce/label/c.Giving_QuickGiftEntry_ErrorTitle';
import errorLoadDefaults from '@salesforce/label/c.Giving_QuickGiftEntry_ErrorLoadDefaults';
import errorUnexpected from '@salesforce/label/c.Giving_QuickGiftEntry_ErrorUnexpected';
import fundNotApplied from '@salesforce/label/c.Giving_QuickGiftEntry_FundNotApplied';
import tributeSection from '@salesforce/label/c.Giving_QuickGiftEntry_TributeSection';
import matchSection from '@salesforce/label/c.Giving_QuickGiftEntry_MatchSection';
import splitSection from '@salesforce/label/c.Giving_QuickGiftEntry_SplitSection';
import HouseholdAddMemberModal from 'c/householdAddMemberModal';
import matchNone from '@salesforce/label/c.Core_AccessCompare_None';
import paysLabel from '@salesforce/label/c.Giving_GiftEntryPays_Label';
import paysNone from '@salesforce/label/c.Giving_GiftEntryPays_None';
import paysOneSuggested from '@salesforce/label/c.Giving_GiftEntryPays_OneSuggested';
import paysSeveralSuggested from '@salesforce/label/c.Giving_GiftEntryPays_SeveralSuggested';
import paysErrorLoad from '@salesforce/label/c.Giving_GiftEntryPays_ErrorLoad';
import { messageFrom } from 'c/findCsv';
import { iconFor } from 'c/barnIcons';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const IN_KIND = 'In-kind';
/** How long typing has to pause before the donor's payments are looked up again. */
const PAYMENT_LOOKUP_DELAY_MS = 300;
const PERSON = 'person';
const ORGANIZATION = 'organization';
const ACCOUNT = 'Account';
const CONTACT = 'Contact';
/** The key prefix of a contact id, so a donor id with no object name still says what it is. */
const CONTACT_PREFIX = '003';
const TRIBUTE_FIELDS = ['tributeType', 'honoreeId', 'honoreeName', 'notifyId', 'notifyName'];

/**
 * Secondary fields shown under each name in the donor pickers (people-giving-1), so two people
 * with the same name can be told apart: email and city for a person, city for an organization.
 */
const CONTACT_DISPLAY_INFO = { additionalFields: ['Email', 'MailingCity'] };
const PERSON_ACCOUNT_DISPLAY_INFO = { additionalFields: ['PersonEmail', 'BillingCity'] };
const ORGANIZATION_DISPLAY_INFO = { additionalFields: ['BillingCity'] };

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
  ['fundId', 'fund'],
  ['tributeType', 'tribute-type'],
  ['honoree', 'honoree', 'honoree-name'],
  ['matchedGiftId', 'matched-gift'],
  ['allocations', 'split']
];

/** Which collapsed section holds the field a message is about, so it can be opened. */
const SECTION_OF = {
  tributeType: 'tribute',
  honoree: 'tribute',
  matchedGiftId: 'match',
  allocations: 'split'
};

/**
 * One line of the "Matches an Employee's Gift" list: who gave, how much and when, then the
 * gift's own name. Framework free, so it ports with the rest of the form's logic (plan 9.9).
 */
export function matchChoiceLabel(choice, locale, currency) {
  const parts = [];
  if (choice.donorName) {
    parts.push(choice.donorName);
  }
  if (choice.amount !== null && choice.amount !== undefined) {
    try {
      parts.push(
        new Intl.NumberFormat(locale, { style: 'currency', currency }).format(choice.amount)
      );
    } catch {
      parts.push(Number(choice.amount).toFixed(2));
    }
  }
  if (choice.giftDate) {
    try {
      parts.push(
        new Intl.DateTimeFormat(locale, { dateStyle: 'medium', timeZone: 'UTC' }).format(
          new Date(choice.giftDate)
        )
      );
    } catch {
      parts.push(choice.giftDate);
    }
  }
  return `${parts.join(', ')} (${choice.name})`;
}

/**
 * Quick gift entry (G-03): one screen, built for a phone, for a gift that has just
 * arrived. Defaults come from BarnCRM Settings, validation messages come back from the
 * controller and are set on the field that caused them through the base components' own
 * validity, so each message is announced and tied to its field.
 *
 * The donor starts filled in when the form knows who gave: on a person's or an
 * organization's page (recordId), from the Enter a Gift action there, or on the Quick Gift
 * Entry tab opened with c__donorId in the page state (people-giving-12).
 */
export default class QuickGiftEntry extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded('Giving');

  /** The object of the record page the component sits on, when it sits on one. */
  @api objectApiName;
  /** True inside the Enter a Gift action, whose window already carries the title. */
  @api inAction = false;

  /** Set when the component sits on a record page, so the donor can be filled in. */
  @api
  get recordId() {
    return this.pageRecordId;
  }
  set recordId(value) {
    this.pageRecordId = value;
    if (this.connected && value) {
      this.prefillDonor(value, this.objectApiName);
    }
  }

  pageRecordId;
  connected = false;
  /** The donor named in the page state the last time it was read. */
  stateDonorId;

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
    get inKindDescriptionHelp() {
      return helpText('Giving', 'Giving_QuickGiftEntry_InKindDescriptionHelp');
    },
    fairMarketValueLabel,
    get fairMarketValueHelp() {
      return helpText('Giving', 'Giving_QuickGiftEntry_FairMarketValueHelp');
    },
    saveButton,
    saveAndNewButton,
    savingMessage,
    errorTitle,
    openGiftLink,
    paysLabel,
    get paysHelp() {
      return helpText('Giving', 'Giving_GiftEntryPays_Help');
    },
    paysErrorLoad,
    tributeSection,
    matchSection,
    get matchHelp() {
      return helpText('Giving', 'Giving_QuickGiftEntry_MatchHelp');
    },
    get matchEmpty() {
      return helpText('Giving', 'Giving_QuickGiftEntry_MatchEmpty');
    },
    splitSection
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

  /** The tribute this gift honors (people-giving-23); all empty means none. */
  tributeType;
  honoreeId;
  honoreeName;
  notifyId;
  notifyName;
  /** The employee's gift an organization's gift matches (R-G11). */
  matchedGiftId = '';
  matchChoices = [];
  matchLoaded = false;
  matchLookup = 0;
  /** The funds the gift is split across (people-giving-16), as { fundId, amount }. */
  allocations = [];
  /** The collapsed sections the person has opened. */
  openSections = [];

  giftTypeOptions = [];
  tributeTypeOptions = [];
  fieldLabels = {};
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

  /** The Quick Gift Entry tab opened for a known donor: c__donorId in the page state. */
  @wire(CurrentPageReference)
  readPageState(pageRef) {
    const donorId = pageRef && pageRef.state ? pageRef.state.c__donorId : undefined;
    if (!donorId || donorId === this.stateDonorId) {
      return;
    }
    this.stateDonorId = donorId;
    if (!this.pageRecordId) {
      this.prefillDonor(donorId);
    }
  }

  connectedCallback() {
    this.connected = true;
    if (!this.helpReady) {
      loadHelp('Giving').then(() => {
        this.helpReady = true;
      });
    }
    if (this.pageRecordId) {
      this.prefillDonor(this.pageRecordId, this.objectApiName);
    }
    this.loadDefaults();
  }

  disconnectedCallback() {
    this.connected = false;
    clearTimeout(this.paymentTimer);
  }

  get cardTitle() {
    return this.inAction ? undefined : heading;
  }

  get cardIcon() {
    return this.inAction ? undefined : iconFor('Quick_Gift_Entry');
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

  get personDisplayInfo() {
    return this.hasPersonAccounts ? PERSON_ACCOUNT_DISPLAY_INFO : CONTACT_DISPLAY_INFO;
  }

  get organizationDisplayInfo() {
    return ORGANIZATION_DISPLAY_INFO;
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

  get honoreeLabel() {
    return this.hasPersonAccounts
      ? this.fieldLabels.honoreeAccount
      : this.fieldLabels.honoreeContact;
  }

  get notifyLabel() {
    return this.hasPersonAccounts ? this.fieldLabels.notifyAccount : this.fieldLabels.notifyContact;
  }

  /** An organization's gift can match an employee's; a person's cannot (R-G11). */
  get showMatch() {
    return this.donorKind === ORGANIZATION && Boolean(this.donorId) && this.isMoneyGift;
  }

  get hasMatchChoices() {
    return this.matchChoices.length > 0;
  }

  get matchOptions() {
    return [
      { label: matchNone, value: '' },
      ...this.matchChoices.map((choice) => ({
        label: matchChoiceLabel(choice, LOCALE, CURRENCY),
        value: choice.id
      }))
    ];
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
    this.forgetMatch();
  }

  handleDonorChange(event) {
    this.markChanged(event);
    this.donorId = event.detail ? event.detail.recordId : undefined;
    this.forgetPayment();
    this.schedulePaymentLookup();
    this.forgetMatch();
    this.lookUpMatches();
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

  handleSectionToggle(event) {
    const open = event.detail ? event.detail.openSections : [];
    this.openSections = Array.isArray(open) ? open : [open].filter(Boolean);
  }

  /** Any field of the tribute section: a record picker sends recordId, the rest value. */
  handleTributeField(event) {
    this.markChanged(event);
    const field = event.target.dataset.field;
    if (!TRIBUTE_FIELDS.includes(field)) {
      return;
    }
    const detail = event.detail || {};
    this[field] = detail.recordId !== undefined ? detail.recordId : detail.value;
  }

  handleMatchChange(event) {
    this.markChanged(event);
    this.matchedGiftId = event.detail.value || '';
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

  /** Another donor has other employees: the gift matched for the last one goes. */
  forgetMatch() {
    this.matchLookup += 1;
    this.matchChoices = [];
    this.matchLoaded = false;
    this.matchedGiftId = '';
  }

  /**
   * Asks for the gifts this organization's gift can match. Only the latest answer is used, and
   * a failure leaves the section empty: the gift still saves, and the match can be linked from
   * the gift page later.
   */
  async lookUpMatches() {
    if (this.donorKind !== ORGANIZATION || !this.donorId) {
      return;
    }
    const lookup = ++this.matchLookup;
    try {
      const choices = await getMatchableGifts({ organizationId: this.donorId });
      if (lookup === this.matchLookup) {
        this.matchChoices = Array.isArray(choices) ? choices : [];
        this.matchLoaded = true;
      }
    } catch {
      if (lookup === this.matchLookup) {
        this.matchChoices = [];
        this.matchLoaded = true;
      }
    }
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
      this.matchedGiftId = '';
      this.allocations = [];
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

  /** Two or more funds make a split; it then replaces the single Fund for this gift. */
  get isSplit() {
    return this.isMoneyGift && this.allocations.length > 1;
  }

  get splitError() {
    return this.fieldErrors.allocations;
  }

  handleSplitChange(event) {
    this.markChanged(event);
    const detail = event.detail || {};
    this.allocations = Array.isArray(detail.allocations) ? detail.allocations : [];
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

  /**
   * New person (people-giving-13): a window over this form creates the person and makes them
   * the donor, so nothing typed so far is lost. Where people are accounts, the standard new
   * record form is used instead, because the window creates a contact.
   */
  async handleNewPerson() {
    if (!this.hasPersonAccounts) {
      const created = await HouseholdAddMemberModal.open({
        label: newPerson,
        size: 'small',
        mode: 'person'
      });
      if (created && created.id) {
        this.markChanged();
        this.donorKind = PERSON;
        this.donorId = created.id;
        this.forgetMatch();
        this.schedulePaymentLookup();
      }
      return;
    }
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
      this.tributeTypeOptions = (this.defaults.tributeTypes || []).map((option) => ({
        label: option.label,
        value: option.value
      }));
      this.fieldLabels = this.defaults.fieldLabels || {};
      this.applyDefaults();
    } catch (error) {
      this.formError = messageFrom(error, errorLoadDefaults);
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
   * The donor is someone the person is already looking at: the record page the form sits on,
   * the record the Enter a Gift action was started from, or the c__donorId the tab was opened
   * with. A contact is a person straight away; for an account the controller says whether it
   * is an organization or, where people are accounts, a person.
   */
  prefillDonor(donorId, objectApiName) {
    const isContact =
      objectApiName === CONTACT || (!objectApiName && String(donorId).startsWith(CONTACT_PREFIX));
    if (objectApiName && objectApiName !== CONTACT && objectApiName !== ACCOUNT) {
      return;
    }
    this.prefilledDonorId = donorId;
    this.prefilledDonorKind = isContact ? PERSON : ORGANIZATION;
    this.donorKind = this.prefilledDonorKind;
    this.donorId = donorId;
    this.forgetMatch();
    if (isContact) {
      return;
    }
    this.confirmDonorKind(donorId);
  }

  async confirmDonorKind(donorId) {
    let kind;
    try {
      kind = await getDonorKind({ donorId });
    } catch {
      // The guess stands: an account is an organization unless the controller says otherwise.
      kind = undefined;
    }
    if (this.donorId !== donorId) {
      return;
    }
    if (kind === PERSON || kind === ORGANIZATION) {
      this.prefilledDonorKind = kind;
      this.donorKind = kind;
    }
    this.lookUpMatches();
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
      Toast.show(
        {
          label: successTitle,
          message: successMessage,
          messageLinks: [{ url: this.savedGift.url, label: result.giftName }],
          variant: 'success'
        },
        this
      );
      this.dispatchEvent(
        new CustomEvent('giftsaved', {
          detail: { giftId: result.giftId, startAnother: startAnother === true }
        })
      );
      if (startAnother) {
        this.startAnotherGift();
      }
    } catch (error) {
      this.formError = messageFrom(error, errorUnexpected);
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
      installmentId: this.isMoneyGift && this.installmentId ? this.installmentId : null,
      tributeType: this.tributeType || null,
      honoreeId: this.honoreeId || null,
      honoreeName: this.honoreeName || null,
      notifyId: this.notifyId || null,
      notifyName: this.notifyName || null,
      matchedGiftId: this.showMatch && this.matchedGiftId ? this.matchedGiftId : null,
      allocations: this.isSplit
        ? this.allocations.map((entry) => ({
            fundId: entry.fundId || null,
            amount: this.numberOrNull(entry.amount)
          }))
        : null
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
    this.openSectionsFor(errors);
    this.setFieldErrors(errors);
    this.formError = result && result.formError ? result.formError : undefined;
    if (!this.formError && fieldErrors.length === 0) {
      this.formError = errorUnexpected;
    }
  }

  /** A message on a field inside a collapsed section opens that section, so it can be seen. */
  openSectionsFor(errors) {
    const wanted = Object.keys(errors)
      .map((key) => SECTION_OF[key])
      .filter((section) => section && !this.openSections.includes(section));
    if (wanted.length > 0) {
      this.openSections = [...this.openSections, ...new Set(wanted)];
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
    TRIBUTE_FIELDS.forEach((field) => {
      this[field] = undefined;
    });
    this.allocations = [];
    this.openSections = [];
    this.forgetPayment();
    this.forgetMatch();
    if (this.donorId) {
      this.schedulePaymentLookup();
      this.lookUpMatches();
    }
    this.setFieldErrors({});
    const donor = this.template.querySelector('[data-id="donor-person"]')
      ? this.template.querySelector('[data-id="donor-person"]')
      : this.template.querySelector('[data-id="donor-organization"]');
    if (donor && typeof donor.focus === 'function') {
      donor.focus();
    }
  }
}
