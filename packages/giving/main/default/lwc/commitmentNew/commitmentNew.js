import { LightningElement, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import LOCALE from '@salesforce/i18n/locale';
import CURRENCY from '@salesforce/i18n/currency';
import getDefaults from '@salesforce/apex/CommitmentEntryController.getDefaults';
import preview from '@salesforce/apex/CommitmentEntryController.preview';
import save from '@salesforce/apex/CommitmentEntryController.save';
import FUND_OBJECT from '@salesforce/schema/Fund__c';
import APPEAL_OBJECT from '@salesforce/schema/Appeal__c';
import COMMITMENT_OBJECT from '@salesforce/schema/Commitment__c';

import TITLE from '@salesforce/label/c.Giving_CommitmentNew_Title';
import RECURRING_GIFT from '@salesforce/label/c.Giving_CommitmentNew_RecurringGift';
import AMOUNT_EACH_TIME from '@salesforce/label/c.Giving_CommitmentNew_AmountEachTime';
import LAST_PAYMENT_DATE from '@salesforce/label/c.Giving_CommitmentNew_LastPaymentDate';
import PLEDGE from '@salesforce/label/c.Giving_PledgeReminders_ColumnPledge';
import KIND from '@salesforce/label/c.Core_DataDictionary_ColType';
import DONOR from '@salesforce/label/c.Giving_GiftBatch_ColumnDonor';
import PERSON_LABEL from '@salesforce/label/c.Core_Section_Person';
import ORGANIZATION_LABEL from '@salesforce/label/c.Core_Settings_NavGroup_Organization';
import PLEDGE_TOTAL from '@salesforce/label/c.Giving_AskPipeline_FieldPledgeTotal';
import HOW_OFTEN from '@salesforce/label/c.Giving_AskPipeline_FieldFrequency';
import PAYMENTS from '@salesforce/label/c.Giving_AskPipeline_FieldPayments';
import FIRST_PAYMENT from '@salesforce/label/c.Giving_AskPipeline_FieldFirstPayment';
import START_DATE from '@salesforce/label/c.Core_Shared_StartDate';
import FUND from '@salesforce/label/c.Giving_GiftBatch_ColumnFund';
import APPEAL from '@salesforce/label/c.Giving_QuickGiftEntry_AppealLabel';
import SCHEDULE from '@salesforce/label/c.Giving_SchedulePreview_Title';
import SAVE from '@salesforce/label/c.Core_Kit_Save';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import { bodyMessage } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { iconFor } from 'c/barnIcons';
import {
  PLEDGE as KIND_PLEDGE,
  RECURRING as KIND_RECURRING,
  PERSON,
  ORGANIZATION,
  contextIdFrom,
  isPreviewReady,
  previewFigures,
  toInput
} from 'c/commitmentEntryModel';

const PREVIEW_DELAY_MS = 300;

/**
 * The New Commitment screen (people-giving-11). It replaces the standard form, which asked for
 * the amount of each payment and invited "twelve payments of 1,200 on a 1,200 pledge": a
 * pledge is entered as its total, as on the Ask Pipeline's Record a Pledge, and the schedule it
 * makes is shown before anything is saved. The server builds the record with the same code as
 * Record a Pledge, so both paths behave the same.
 */
export default class CommitmentNew extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded('Giving');

  labels = {
    title: TITLE,
    kind: KIND,
    pledge: PLEDGE,
    recurringGift: RECURRING_GIFT,
    donor: DONOR,
    person: PERSON_LABEL,
    organization: ORGANIZATION_LABEL,
    pledgeTotal: PLEDGE_TOTAL,
    howOften: HOW_OFTEN,
    payments: PAYMENTS,
    lastPaymentDate: LAST_PAYMENT_DATE,
    firstPayment: FIRST_PAYMENT,
    amountEachTime: AMOUNT_EACH_TIME,
    startDate: START_DATE,
    fund: FUND,
    appeal: APPEAL,
    schedule: SCHEDULE,
    save: SAVE,
    cancel: CANCEL,
    get endHelp() {
      return helpText('Giving', 'Giving_CommitmentNew_EndHelp');
    },
    get previewEmpty() {
      return helpText('Giving', 'Giving_CommitmentNew_PreviewEmpty');
    }
  };

  icon = iconFor('Commitment__c');

  loaded = false;
  canCreate = false;
  hasPersonAccounts = false;
  frequencyOptions = [];
  contextId;

  kind = KIND_PLEDGE;
  donorKind = PERSON;
  donorId;
  total;
  payments;
  lastPaymentDate;
  amount;
  frequency;
  startDate;
  fundId;
  appealId;

  previewText;
  saving = false;
  errorMessage;

  previewTimer;
  previewRequest = 0;
  pageStateKey;

  @wire(CurrentPageReference)
  setPageReference(pageReference) {
    const state = pageReference && pageReference.state ? pageReference.state : {};
    const key = JSON.stringify(state);
    // The platform keeps an override's component between visits, so a new visit starts over.
    if (key === this.pageStateKey) {
      return;
    }
    this.pageStateKey = key;
    this.contextId = contextIdFrom(state);
    this.start();
  }

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Giving').then(() => {
        this.helpReady = true;
      });
    }
  }

  disconnectedCallback() {
    clearTimeout(this.previewTimer);
  }

  async start() {
    this.resetEntries();
    this.loaded = false;
    try {
      const defaults = await getDefaults({ contextId: this.contextId || null });
      this.canCreate = defaults.canCreate === true;
      this.hasPersonAccounts = defaults.hasPersonAccounts === true;
      this.frequencyOptions = defaults.frequencies || [];
      this.frequency = defaults.defaultFrequency;
      if (defaults.donorId) {
        this.donorId = defaults.donorId;
        this.donorKind = defaults.donorKind === ORGANIZATION ? ORGANIZATION : PERSON;
      }
    } catch (error) {
      this.errorMessage = bodyMessage(
        error,
        helpText('Giving', 'Giving_CommitmentNew_ErrorUnexpected')
      );
    } finally {
      this.loaded = true;
    }
  }

  resetEntries() {
    this.kind = KIND_PLEDGE;
    this.donorKind = PERSON;
    this.donorId = undefined;
    this.total = undefined;
    this.payments = undefined;
    this.lastPaymentDate = undefined;
    this.amount = undefined;
    this.startDate = undefined;
    this.fundId = undefined;
    this.appealId = undefined;
    this.previewText = undefined;
    this.errorMessage = undefined;
    this.saving = false;
  }

  get kindOptions() {
    return [
      { label: this.labels.pledge, value: KIND_PLEDGE },
      { label: this.labels.recurringGift, value: KIND_RECURRING }
    ];
  }

  get donorKindOptions() {
    return [
      { label: this.labels.person, value: PERSON },
      { label: this.labels.organization, value: ORGANIZATION }
    ];
  }

  get isPledge() {
    return this.kind !== KIND_RECURRING;
  }

  get isPersonDonor() {
    return this.donorKind === PERSON;
  }

  get personObjectApiName() {
    return this.hasPersonAccounts ? 'Account' : 'Contact';
  }

  /** A second line under each name, so two people with one name can be told apart. */
  get personDisplayInfo() {
    return this.hasPersonAccounts
      ? { additionalFields: ['BillingCity'] }
      : { additionalFields: ['Email'] };
  }

  get organizationDisplayInfo() {
    return { additionalFields: ['BillingCity'] };
  }

  get fundObjectApiName() {
    return FUND_OBJECT.objectApiName;
  }

  get appealObjectApiName() {
    return APPEAL_OBJECT.objectApiName;
  }

  get startDateLabel() {
    return this.isPledge ? this.labels.firstPayment : this.labels.startDate;
  }

  get showForm() {
    return this.loaded && this.canCreate;
  }

  get showNoPermission() {
    return this.loaded && !this.canCreate;
  }

  get noPermission() {
    return helpText('Giving', 'Giving_Commitment_NoPermission');
  }

  get saveDisabled() {
    return this.saving;
  }

  handleKindChange(event) {
    this.kind = event.detail.value;
    this.schedulePreview();
  }

  handleDonorKindChange(event) {
    this.donorKind = event.detail.value;
    this.donorId = undefined;
  }

  handleDonorChange(event) {
    this.donorId = event.detail.recordId || undefined;
  }

  handleFundChange(event) {
    this.fundId = event.detail.recordId || undefined;
  }

  handleAppealChange(event) {
    this.appealId = event.detail.recordId || undefined;
  }

  /** Each input names the property it sets in data-field. */
  handleValueChange(event) {
    const field = event.target.dataset.field;
    const value = event.detail.value === '' ? undefined : event.detail.value;
    this[field] = value;
    // The number of payments and the last payment date are two ways to say one thing.
    if (field === 'payments' && value) {
      this.lastPaymentDate = undefined;
    } else if (field === 'lastPaymentDate' && value) {
      this.payments = undefined;
    }
    this.schedulePreview();
  }

  get entry() {
    return {
      kind: this.kind,
      donorKind: this.donorKind,
      donorId: this.donorId,
      total: this.total,
      payments: this.payments,
      lastPaymentDate: this.lastPaymentDate,
      amount: this.amount,
      frequency: this.frequency,
      startDate: this.startDate,
      fundId: this.fundId,
      appealId: this.appealId
    };
  }

  schedulePreview() {
    clearTimeout(this.previewTimer);
    if (!isPreviewReady(this.entry)) {
      this.previewText = undefined;
      return;
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.previewTimer = setTimeout(() => this.loadPreview(), PREVIEW_DELAY_MS);
  }

  async loadPreview() {
    const request = ++this.previewRequest;
    try {
      const result = await preview({ input: toInput(this.entry, this.hasPersonAccounts) });
      if (request === this.previewRequest) {
        this.previewText = this.describe(previewFigures(result));
      }
    } catch {
      if (request === this.previewRequest) {
        this.previewText = undefined;
      }
    }
  }

  /** The preview as one sentence: "12 payments, 100.00 each, the last one 100.00 on 1 Dec 2027." */
  describe(figures) {
    if (!figures) {
      return undefined;
    }
    if (this.isPledge) {
      return helpText(
        'Giving',
        'Giving_CommitmentNew_PreviewPledge',
        String(figures.count),
        this.money(figures.each),
        this.money(figures.lastAmount),
        this.date(figures.lastDate)
      );
    }
    return helpText(
      'Giving',
      'Giving_CommitmentNew_PreviewRecurring',
      this.money(figures.each),
      this.date(figures.firstDate)
    );
  }

  money(value) {
    return new Intl.NumberFormat(LOCALE, { style: 'currency', currency: CURRENCY }).format(
      Number(value) || 0
    );
  }

  date(value) {
    if (!value) {
      return '';
    }
    const [year, month, day] = String(value).split('-').map(Number);
    return new Intl.DateTimeFormat(LOCALE, {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      timeZone: 'UTC'
    }).format(new Date(Date.UTC(year, month - 1, day)));
  }

  /** Checks the inputs the browser can check before asking the server. */
  inputsValid() {
    return [...this.template.querySelectorAll('lightning-input, lightning-combobox')].reduce(
      (valid, input) => input.reportValidity() !== false && valid,
      true
    );
  }

  async handleSave() {
    this.errorMessage = undefined;
    if (!this.inputsValid()) {
      return;
    }
    this.saving = true;
    try {
      const result = await save({ input: toInput(this.entry, this.hasPersonAccounts) });
      if (result.success) {
        this[NavigationMixin.Navigate]({
          type: 'standard__recordPage',
          attributes: { recordId: result.commitmentId, actionName: 'view' }
        });
      } else {
        this.errorMessage = result.error;
      }
    } catch (error) {
      this.errorMessage = bodyMessage(
        error,
        helpText('Giving', 'Giving_CommitmentNew_ErrorUnexpected')
      );
    } finally {
      this.saving = false;
    }
  }

  /** Back to the record New was chosen from, or to the commitments list. */
  handleCancel() {
    if (this.contextId) {
      this[NavigationMixin.Navigate]({
        type: 'standard__recordPage',
        attributes: { recordId: this.contextId, actionName: 'view' }
      });
      return;
    }
    this[NavigationMixin.Navigate]({
      type: 'standard__objectPage',
      attributes: { objectApiName: COMMITMENT_OBJECT.objectApiName, actionName: 'home' }
    });
  }
}
