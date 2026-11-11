import { createElement } from 'lwc';
import Toast from 'lightning/toast';
import { CurrentPageReference } from 'lightning/navigation';
import QuickGiftEntry, { matchChoiceLabel } from 'c/quickGiftEntry';
import getDefaults from '@salesforce/apex/QuickGiftEntryController.getDefaults';
import getDonorKind from '@salesforce/apex/QuickGiftEntryController.getDonorKind';
import getMatchableGifts from '@salesforce/apex/QuickGiftEntryController.getMatchableGifts';
import saveGift from '@salesforce/apex/QuickGiftEntryController.saveGift';
import getPaymentChoices from '@salesforce/apex/QuickGiftEntryController.getPaymentChoices';
import HouseholdAddMemberModal from 'c/householdAddMemberModal';

const mockNavigate = jest.fn();
jest.mock(
  'lightning/navigation',
  () => {
    const { createTestWireAdapter } = require('@salesforce/wire-service-jest-util');
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) =>
      class extends Base {
        [Navigate](...args) {
          mockNavigate(...args);
        }
      };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin, CurrentPageReference: createTestWireAdapter(), __esModule: true };
  },
  { virtual: true }
);

jest.mock('@salesforce/apex/QuickGiftEntryController.getDefaults', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock(
  '@salesforce/apex/QuickGiftEntryController.getDonorKind',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/QuickGiftEntryController.getMatchableGifts',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock('@salesforce/apex/QuickGiftEntryController.saveGift', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock(
  '@salesforce/apex/QuickGiftEntryController.getPaymentChoices',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

// The donor panel child (G-33) loads on its own; the form tests only need it quiet.
jest.mock(
  '@salesforce/apex/GiftDonorPanelController.getPanel',
  () => ({ default: jest.fn(() => Promise.resolve(null)) }),
  { virtual: true }
);

const DEFAULTS = {
  giftDate: '2026-09-07',
  hasPersonAccounts: false,
  defaultFundId: '001000000000000AAA',
  defaultFundName: 'Annual Fund',
  defaultAppealId: '002000000000000AAA',
  defaultAppealName: 'Spring Appeal',
  giftTypes: [
    { label: 'Cash', value: 'Cash' },
    { label: 'Check', value: 'Check' },
    { label: 'In-kind', value: 'In-kind' }
  ],
  tributeTypes: [
    { label: 'In honor of', value: 'In honor of' },
    { label: 'In memory of', value: 'In memory of' }
  ],
  fieldLabels: {
    tributeType: 'Type',
    honoreeContact: 'Honoree Contact',
    honoreeAccount: 'Honoree Account',
    honoreeName: 'Honoree Name',
    notifyContact: 'Notification Recipient Contact',
    notifyAccount: 'Notification Recipient Account',
    notifyName: 'Notification Recipient Name',
    matchedGift: 'Matched Gift'
  }
};

const CONTACT_ID = '003000000000000AAA';
const ACCOUNT_ID = '001000000000000BBB';

function build(props = {}) {
  const element = createElement('c-quick-gift-entry', { is: QuickGiftEntry });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

function pick(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

/** Records the messages a base component is given through its own validity methods. */
function watchValidity(field) {
  field.setCustomValidity = jest.fn();
  field.reportValidity = jest.fn();
  return field;
}

function change(target, detail) {
  target.dispatchEvent(new CustomEvent('change', { detail }));
}

async function settle() {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
}

async function enterAnInKindGift(element) {
  change(pick(element, 'donor-person'), { recordId: CONTACT_ID });
  change(pick(element, 'gift-type'), { value: 'In-kind' });
  await settle();
  change(pick(element, 'in-kind-description'), { value: 'Sixteen folding tables, used' });
  change(pick(element, 'fair-market-value'), { value: '800' });
  await settle();
}

async function enterAGift(element) {
  change(pick(element, 'donor-person'), { recordId: CONTACT_ID });
  change(pick(element, 'amount'), { value: '50' });
  change(pick(element, 'gift-type'), { value: 'Check' });
  await settle();
}

describe('c-quick-gift-entry', () => {
  beforeEach(() => {
    getDefaults.mockResolvedValue({ ...DEFAULTS });
    getDonorKind.mockResolvedValue('organization');
    getMatchableGifts.mockResolvedValue([]);
    saveGift.mockResolvedValue({
      success: true,
      giftId: '004000000000000AAA',
      giftName: 'G-000123',
      fieldErrors: []
    });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('starts from the defaults the controller returns', async () => {
    const element = build();
    await settle();

    expect(getDefaults).toHaveBeenCalled();
    expect(pick(element, 'gift-date').value).toBe(DEFAULTS.giftDate);
    expect(pick(element, 'appeal').value).toBe(DEFAULTS.defaultAppealId);
    expect(pick(element, 'fund').value).toBe(DEFAULTS.defaultFundId);
    expect(pick(element, 'gift-type').options).toEqual(DEFAULTS.giftTypes);
  });

  it('searches contacts for the donor, and accounts where people are accounts', async () => {
    const contactOrg = build();
    await settle();
    expect(pick(contactOrg, 'donor-person').objectApiName).toBe('Contact');

    getDefaults.mockResolvedValue({ ...DEFAULTS, hasPersonAccounts: true });
    const personAccountOrg = build();
    await settle();
    expect(pick(personAccountOrg, 'donor-person').objectApiName).toBe('Account');
  });

  it('says the defaults could not be read when the controller fails', async () => {
    getDefaults.mockRejectedValue({ body: { message: 'Settings are unavailable.' } });
    const element = build();
    await settle();

    expect(pick(element, 'form-error').message).toContain('Settings are unavailable.');
    expect(pick(element, 'form-error').variant).toBe('error');
  });

  it('shows the controller validation messages beside their fields', async () => {
    saveGift.mockResolvedValue({
      success: false,
      fieldErrors: [
        { field: 'donor', message: 'Choose the person or organization who gave this gift.' },
        {
          field: 'amount',
          message:
            'Enter an amount greater than zero. A refund is entered from the original gift, not here.'
        }
      ]
    });
    const element = build();
    await settle();
    const donor = watchValidity(pick(element, 'donor-person'));
    const amount = watchValidity(pick(element, 'amount'));
    const giftDate = watchValidity(pick(element, 'gift-date'));

    pick(element, 'save').click();
    await settle();

    expect(donor.setCustomValidity).toHaveBeenLastCalledWith(
      'Choose the person or organization who gave this gift.'
    );
    expect(donor.reportValidity).toHaveBeenCalled();
    expect(amount.setCustomValidity).toHaveBeenLastCalledWith(
      'Enter an amount greater than zero. A refund is entered from the original gift, not here.'
    );
    expect(amount.reportValidity).toHaveBeenCalled();
    expect(giftDate.setCustomValidity).toHaveBeenLastCalledWith('');
    expect(giftDate.reportValidity).not.toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('[data-id^="error-"]')).toBeNull();
    expect(pick(element, 'saved')).toBeNull();
  });

  it('takes the message off a field as soon as the person changes it', async () => {
    saveGift.mockResolvedValue({
      success: false,
      fieldErrors: [{ field: 'amount', message: 'Enter an amount greater than zero.' }]
    });
    const element = build();
    await settle();
    const amount = watchValidity(pick(element, 'amount'));
    pick(element, 'save').click();
    await settle();
    expect(amount.setCustomValidity).toHaveBeenLastCalledWith('Enter an amount greater than zero.');

    change(amount, { value: '40' });
    await settle();

    expect(amount.setCustomValidity).toHaveBeenLastCalledWith('');
    expect(amount.reportValidity).toHaveBeenCalledTimes(2);
  });

  it('creates a new person in a window and makes them the donor, keeping what was typed', async () => {
    HouseholdAddMemberModal.open.mockResolvedValueOnce({ id: CONTACT_ID, name: 'Ana Garcia' });
    const element = build();
    await settle();
    change(pick(element, 'amount'), { value: '75' });

    pick(element, 'new-person').click();
    await settle();

    expect(HouseholdAddMemberModal.open).toHaveBeenCalledWith(
      expect.objectContaining({ mode: 'person', size: 'small' })
    );
    expect(mockNavigate).not.toHaveBeenCalled();
    expect(pick(element, 'donor-person').value).toBe(CONTACT_ID);
    expect(pick(element, 'amount').value).toBe('75');
  });

  it('leaves the donor alone when the New Person window closes without a person', async () => {
    HouseholdAddMemberModal.open.mockResolvedValueOnce(undefined);
    const element = build();
    await settle();

    pick(element, 'new-person').click();
    await settle();

    expect(pick(element, 'donor-person').value).toBeFalsy();
  });

  it('opens the standard new person form where people are person accounts', async () => {
    getDefaults.mockResolvedValue({ ...DEFAULTS, hasPersonAccounts: true });
    const element = build();
    await settle();

    pick(element, 'new-person').click();

    expect(HouseholdAddMemberModal.open).not.toHaveBeenCalled();
    const pageReference = mockNavigate.mock.calls[0][0];
    expect(pageReference.type).toBe('standard__objectPage');
    expect(pageReference.attributes).toEqual({ objectApiName: 'Account', actionName: 'new' });
    expect(pageReference.state.navigationLocation).toBe('RELATED_LIST');
  });

  it('sends a split across funds and turns the single Fund off while it applies', async () => {
    const element = build();
    await settle();
    await enterAGift(element);

    change(pick(element, 'split'), {
      allocations: [
        { fundId: 'a01000000000001AAA', amount: '30' },
        { fundId: 'a01000000000002AAA', amount: 20 }
      ],
      valid: true
    });
    await settle();
    expect(pick(element, 'fund').disabled).toBe(true);

    pick(element, 'save').click();
    await settle();

    expect(saveGift.mock.calls[0][0].input.allocations).toEqual([
      { fundId: 'a01000000000001AAA', amount: 30 },
      { fundId: 'a01000000000002AAA', amount: 20 }
    ]);
  });

  it('shows the controller message about a split inside the split section', async () => {
    saveGift.mockResolvedValue({
      success: false,
      fieldErrors: [{ field: 'allocations', message: 'Make the rows add up.' }]
    });
    const element = build();
    await settle();
    await enterAGift(element);
    change(pick(element, 'split'), {
      allocations: [
        { fundId: 'a01000000000001AAA', amount: 30 },
        { fundId: 'a01000000000002AAA', amount: 10 }
      ],
      valid: false
    });
    await settle();

    pick(element, 'save').click();
    await settle();

    expect(pick(element, 'split-error').message).toBe('Make the rows add up.');
  });

  it('offers a new person only while the donor is a person', async () => {
    const element = build();
    await settle();
    expect(pick(element, 'new-person')).not.toBeNull();

    change(pick(element, 'donor-kind'), { value: 'organization' });
    await settle();

    expect(pick(element, 'new-person')).toBeNull();
  });

  it('saves the gift the person entered and confirms it with a link', async () => {
    const element = build();
    await settle();
    const toast = jest.spyOn(Toast, 'show');

    await enterAGift(element);
    pick(element, 'save').click();
    await settle();

    expect(saveGift).toHaveBeenCalledWith({
      input: {
        donorContactId: CONTACT_ID,
        donorAccountId: null,
        amount: 50,
        giftDate: '2026-09-07',
        giftType: 'Check',
        appealId: DEFAULTS.defaultAppealId,
        fundId: DEFAULTS.defaultFundId,
        paymentReference: null,
        inKindDescription: null,
        fairMarketValue: null,
        installmentId: null,
        tributeType: null,
        honoreeId: null,
        honoreeName: null,
        notifyId: null,
        notifyName: null,
        matchedGiftId: null,
        allocations: null
      }
    });
    expect(pick(element, 'saved')).not.toBeNull();
    expect(pick(element, 'saved').variant).toBe('success');
    expect(pick(element, 'saved').actionHref).toContain('/lightning/r/Gift__c/');
    expect(toast).toHaveBeenCalled();
    expect(toast.mock.calls[0][0].messageLinks[0].label).toBe('G-000123');
    expect(toast.mock.calls[0][0].messageLinks[0].url).toContain('004000000000000AAA');
  });

  it('clears the donor and the amount after save and new, and keeps the date and fund', async () => {
    const element = build();
    await settle();

    await enterAGift(element);
    pick(element, 'save-and-new').click();
    await settle();

    expect(pick(element, 'amount').value).toBeUndefined();
    expect(pick(element, 'donor-person').value).toBeUndefined();
    expect(pick(element, 'gift-date').value).toBe(DEFAULTS.giftDate);
    expect(pick(element, 'fund').value).toBe(DEFAULTS.defaultFundId);
  });

  it('shows what went wrong when the save itself fails', async () => {
    saveGift.mockRejectedValue({ body: { message: 'Insufficient access on Gift.' } });
    const element = build();
    await settle();

    await enterAGift(element);
    pick(element, 'save').click();
    await settle();

    expect(pick(element, 'form-error').message).toContain('Insufficient access on Gift.');
    expect(pick(element, 'saved')).toBeNull();
  });

  it('will not enter the same gift twice when Save is tapped again', async () => {
    const element = build();
    await settle();

    await enterAGift(element);
    pick(element, 'save').click();
    await settle();

    expect(saveGift).toHaveBeenCalledTimes(1);
    expect(pick(element, 'save').disabled).toBe(true);
    expect(pick(element, 'save-and-new').disabled).toBe(true);

    pick(element, 'save').click();
    await settle();
    expect(saveGift).toHaveBeenCalledTimes(1);

    change(pick(element, 'amount'), { value: '75' });
    await settle();
    expect(pick(element, 'save').disabled).toBe(false);

    pick(element, 'save').click();
    await settle();
    expect(saveGift).toHaveBeenCalledTimes(2);
  });

  it('is ready for the next gift straight after save and new', async () => {
    const element = build();
    await settle();

    await enterAGift(element);
    pick(element, 'save-and-new').click();
    await settle();

    expect(pick(element, 'save-and-new').disabled).toBe(false);
  });

  it('moves the keyboard to the first field that has a message', async () => {
    saveGift.mockResolvedValue({
      success: false,
      fieldErrors: [
        { field: 'amount', message: 'Enter an amount greater than zero.' },
        { field: 'giftType', message: 'Choose how the gift arrived.' }
      ]
    });
    const element = build();
    await settle();
    const focus = jest.fn();
    pick(element, 'amount').focus = focus;

    pick(element, 'save').click();
    await settle();

    expect(focus).toHaveBeenCalled();
  });

  it('replaces the amount with a description and a value when the gift is goods', async () => {
    const element = build();
    await settle();

    expect(pick(element, 'amount')).not.toBeNull();
    expect(pick(element, 'in-kind-description')).toBeNull();

    change(pick(element, 'gift-type'), { value: 'In-kind' });
    await settle();

    expect(pick(element, 'amount')).toBeNull();
    expect(pick(element, 'in-kind-description')).not.toBeNull();
    expect(pick(element, 'in-kind-description').required).toBe(true);
    expect(pick(element, 'fair-market-value')).not.toBeNull();
    expect(pick(element, 'fair-market-value').required).toBeFalsy();
  });

  it('shows a note beside the value box, from the packaged label rather than in the markup', async () => {
    const element = build();
    await settle();

    change(pick(element, 'gift-type'), { value: 'In-kind' });
    await settle();

    // Jest resolves a custom label to its own name, so this asserts that the note is rendered
    // and that it comes from the label an administrator can translate, not from English typed
    // into the template.
    expect(pick(element, 'fair-market-value-help').textContent).toBe(
      'c.Giving_QuickGiftEntry_FairMarketValueHelp'
    );
    expect(pick(element, 'in-kind-description').fieldLevelHelp).toBe(
      'c.Giving_QuickGiftEntry_InKindDescriptionHelp'
    );
  });

  it('sends a gift of goods with a zero amount and the two in-kind values', async () => {
    const element = build();
    await settle();

    await enterAnInKindGift(element);
    pick(element, 'save').click();
    await settle();

    expect(saveGift).toHaveBeenCalledTimes(1);
    const sent = saveGift.mock.calls[0][0].input;
    expect(sent.amount).toBe(0);
    expect(sent.giftType).toBe('In-kind');
    expect(sent.inKindDescription).toBe('Sixteen folding tables, used');
    expect(sent.fairMarketValue).toBe(800);
  });

  it('does not send an in-kind description on a gift of money', async () => {
    const element = build();
    await settle();

    await enterAnInKindGift(element);
    change(pick(element, 'gift-type'), { value: 'Check' });
    await settle();
    change(pick(element, 'amount'), { value: '250' });
    await settle();

    pick(element, 'save').click();
    await settle();

    const sent = saveGift.mock.calls[0][0].input;
    expect(sent.amount).toBe(250);
    expect(sent.inKindDescription).toBeNull();
    expect(sent.fairMarketValue).toBeNull();
  });

  it('shows the controller message beside the description that is missing', async () => {
    saveGift.mockResolvedValue({
      success: false,
      fieldErrors: [{ field: 'inKindDescription', message: 'Describe what was given.' }]
    });
    const element = build();
    await settle();

    change(pick(element, 'donor-person'), { recordId: CONTACT_ID });
    change(pick(element, 'gift-type'), { value: 'In-kind' });
    await settle();
    const description = watchValidity(pick(element, 'in-kind-description'));
    pick(element, 'save').click();
    await settle();

    expect(description.setCustomValidity).toHaveBeenLastCalledWith('Describe what was given.');
    expect(description.reportValidity).toHaveBeenCalled();
  });

  it('says so when the gift saved but the fund chosen could not be applied', async () => {
    saveGift.mockResolvedValue({
      success: true,
      giftId: '004000000000000AAA',
      giftName: 'G-000124',
      fundNotApplied: true,
      fieldErrors: []
    });
    const element = build();
    await settle();

    await enterAGift(element);
    pick(element, 'save').click();
    await settle();

    expect(pick(element, 'saved')).not.toBeNull();
    expect(pick(element, 'save-warning')).not.toBeNull();
  });

  it('starts with the person whose page it sits on as the donor', async () => {
    const element = build({ recordId: CONTACT_ID, objectApiName: 'Contact' });
    await settle();

    expect(pick(element, 'donor-kind').value).toBe('person');
    expect(pick(element, 'donor-person').value).toBe(CONTACT_ID);
    expect(pick(element, 'donor-person').displayInfo).toEqual({
      additionalFields: ['Email', 'MailingCity']
    });
    expect(getDonorKind).not.toHaveBeenCalled();
  });

  it('asks whether an account is a person or an organization, and offers its matches', async () => {
    getMatchableGifts.mockResolvedValue([
      {
        id: 'a05000000000001AAA',
        name: 'G-000042',
        donorName: 'Ana Garcia',
        amount: 100,
        giftDate: '2026-10-01'
      }
    ]);
    const element = build({ recordId: ACCOUNT_ID, objectApiName: 'Account' });
    await settle();

    expect(getDonorKind).toHaveBeenCalledWith({ donorId: ACCOUNT_ID });
    expect(pick(element, 'donor-organization').value).toBe(ACCOUNT_ID);
    expect(pick(element, 'donor-organization').displayInfo).toEqual({
      additionalFields: ['BillingCity']
    });
    expect(getMatchableGifts).toHaveBeenCalledWith({ organizationId: ACCOUNT_ID });
    const matched = pick(element, 'matched-gift');
    expect(matched.options.map((option) => option.value)).toEqual(['', 'a05000000000001AAA']);

    change(pick(element, 'amount'), { value: '100' });
    change(pick(element, 'gift-type'), { value: 'Check' });
    change(matched, { value: 'a05000000000001AAA' });
    pick(element, 'save').click();
    await settle();

    const sent = saveGift.mock.calls[0][0].input;
    expect(sent.donorAccountId).toBe(ACCOUNT_ID);
    expect(sent.matchedGiftId).toBe('a05000000000001AAA');
  });

  it('treats a person account as a person and offers no match', async () => {
    getDonorKind.mockResolvedValue('person');
    getDefaults.mockResolvedValue({ ...DEFAULTS, hasPersonAccounts: true });
    const element = build({ recordId: ACCOUNT_ID, objectApiName: 'Account' });
    await settle();

    expect(pick(element, 'donor-kind').value).toBe('person');
    expect(pick(element, 'donor-person').value).toBe(ACCOUNT_ID);
    expect(pick(element, 'match-section')).toBeNull();
  });

  it('starts with the donor named in the page state on the Quick Gift Entry tab', async () => {
    const element = build();
    await settle();

    // eslint-disable-next-line @lwc/lwc/no-unexpected-wire-adapter-usages
    CurrentPageReference.emit({ type: 'standard__navItemPage', state: { c__donorId: CONTACT_ID } });
    await settle();

    expect(pick(element, 'donor-person').value).toBe(CONTACT_ID);
  });

  it('sends the tribute typed in the honors section, and says when the gift saved', async () => {
    const element = build();
    const saved = jest.fn();
    element.addEventListener('giftsaved', saved);
    await settle();
    expect(pick(element, 'tribute-type').options.map((option) => option.value)).toEqual([
      'In honor of',
      'In memory of'
    ]);
    expect(pick(element, 'honoree').label).toBe('Honoree Contact');

    await enterAGift(element);
    change(pick(element, 'tribute-type'), { value: 'In memory of' });
    change(pick(element, 'honoree-name'), { value: 'Rosa Garcia' });
    change(pick(element, 'notify'), { recordId: '003000000000000CCC' });
    pick(element, 'save').click();
    await settle();

    const sent = saveGift.mock.calls[0][0].input;
    expect(sent.tributeType).toBe('In memory of');
    expect(sent.honoreeName).toBe('Rosa Garcia');
    expect(sent.honoreeId).toBeNull();
    expect(sent.notifyId).toBe('003000000000000CCC');
    expect(sent.matchedGiftId).toBeNull();
    expect(saved).toHaveBeenCalled();
    expect(saved.mock.calls[0][0].detail).toEqual({
      giftId: '004000000000000AAA',
      startAnother: false
    });
  });

  it('opens the honors section when a message is about one of its fields', async () => {
    saveGift.mockResolvedValue({
      success: false,
      fieldErrors: [{ field: 'honoree', message: 'Say who this gift honors.' }]
    });
    const element = build();
    await settle();
    expect(pick(element, 'more').activeSectionName).toEqual([]);

    await enterAGift(element);
    change(pick(element, 'tribute-type'), { value: 'In honor of' });
    pick(element, 'save').click();
    await settle();

    expect(pick(element, 'more').activeSectionName).toEqual(['tribute']);
  });

  it('writes a match choice as donor, amount and date, then the gift name', () => {
    const label = matchChoiceLabel(
      { name: 'G-000042', donorName: 'Ana Garcia', amount: 100, giftDate: '2026-10-01' },
      'en-US',
      'USD'
    );
    expect(label).toBe('Ana Garcia, $100.00, Oct 1, 2026 (G-000042)');
  });

  it('drops the card title inside the Enter a Gift action, whose window has one', async () => {
    const element = build({ inAction: true });
    await settle();
    expect(element.shadowRoot.querySelector('lightning-card').title).toBeUndefined();
  });

  describe('pays a scheduled payment', () => {
    const MARCH = 'a01000000000001AAA';
    const APRIL = 'a01000000000002AAA';
    const choicesWith = (suggested) => ({
      choices: [
        {
          value: MARCH,
          label: 'Pledge CM-000001, payment 1, due 3/15/2026, 50.00 expected',
          suggested: suggested.includes(MARCH)
        },
        {
          value: APRIL,
          label: 'Pledge CM-000001, payment 2, due 4/15/2026, 50.00 expected',
          suggested: suggested.includes(APRIL)
        }
      ],
      suggestedId: suggested.length === 1 ? suggested[0] : null,
      suggestedCount: suggested.length
    });

    /** Lets the pause before a lookup pass, and the lookup answer. */
    async function lookUp() {
      jest.runOnlyPendingTimers();
      await settle();
    }

    beforeEach(() => {
      jest.useFakeTimers();
      getPaymentChoices.mockResolvedValue(choicesWith([MARCH]));
    });

    afterEach(() => {
      jest.useRealTimers();
    });

    it('shows no list until a donor who owes a payment is chosen', async () => {
      getPaymentChoices.mockResolvedValue({ choices: [], suggestedId: null, suggestedCount: 0 });
      const element = build();
      await settle();
      expect(pick(element, 'pays')).toBeNull();

      await enterAGift(element);
      await lookUp();

      expect(getPaymentChoices).toHaveBeenCalledWith({
        donorContactId: CONTACT_ID,
        donorAccountId: null,
        giftDate: '2026-09-07',
        amount: 50
      });
      expect(pick(element, 'pays')).toBeNull();
    });

    it('chooses the only suggestion in advance, on screen, and says why', async () => {
      const element = build();
      await settle();

      await enterAGift(element);
      await lookUp();

      const pays = pick(element, 'pays');
      expect(pays.value).toBe(MARCH);
      expect(pays.options[0].value).toBe('');
      expect(pays.options.map((option) => option.value)).toEqual(['', MARCH, APRIL]);
      expect(pick(element, 'pays-note').textContent).not.toBe('');

      pick(element, 'save').click();
      await settle();
      expect(saveGift.mock.calls[0][0].input.installmentId).toBe(MARCH);
    });

    it('chooses nothing when two payments are suggested', async () => {
      getPaymentChoices.mockResolvedValue(choicesWith([MARCH, APRIL]));
      const element = build();
      await settle();

      await enterAGift(element);
      await lookUp();

      expect(pick(element, 'pays').value).toBe('');
      pick(element, 'save').click();
      await settle();
      expect(saveGift.mock.calls[0][0].input.installmentId).toBeNull();
    });

    it('keeps None once the person chose it, when the amount changes', async () => {
      const element = build();
      await settle();
      await enterAGift(element);
      await lookUp();

      change(pick(element, 'pays'), { value: '' });
      change(pick(element, 'amount'), { value: '50.00' });
      await lookUp();

      expect(pick(element, 'pays').value).toBe('');
      pick(element, 'save').click();
      await settle();
      expect(saveGift.mock.calls[0][0].input.installmentId).toBeNull();
    });

    it('forgets the choice when the donor changes', async () => {
      const element = build();
      await settle();
      await enterAGift(element);
      await lookUp();
      getPaymentChoices.mockResolvedValue({ choices: [], suggestedId: null, suggestedCount: 0 });

      change(pick(element, 'donor-person'), { recordId: '003000000000000BBB' });
      await lookUp();

      expect(pick(element, 'pays')).toBeNull();
      pick(element, 'save').click();
      await settle();
      expect(saveGift.mock.calls[0][0].input.installmentId).toBeNull();
    });

    it('sends no payment with a gift of goods', async () => {
      const element = build();
      await settle();
      await enterAGift(element);
      await lookUp();

      change(pick(element, 'gift-type'), { value: 'In-kind' });
      await settle();
      expect(pick(element, 'pays')).toBeNull();
      change(pick(element, 'in-kind-description'), { value: 'Two chairs' });
      pick(element, 'save').click();
      await settle();
      expect(saveGift.mock.calls[0][0].input.installmentId).toBeNull();
    });

    it('says the payments could not be loaded and still lets the gift be saved', async () => {
      getPaymentChoices.mockRejectedValue({ body: { message: 'boom' } });
      const element = build();
      await settle();
      await enterAGift(element);
      await lookUp();

      expect(pick(element, 'pays-error')).not.toBeNull();
      expect(pick(element, 'save').disabled).toBe(false);
    });
  });
});
