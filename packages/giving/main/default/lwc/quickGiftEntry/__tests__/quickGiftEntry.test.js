import { createElement } from 'lwc';
import QuickGiftEntry from 'c/quickGiftEntry';
import getDefaults from '@salesforce/apex/QuickGiftEntryController.getDefaults';
import saveGift from '@salesforce/apex/QuickGiftEntryController.saveGift';
import getPaymentChoices from '@salesforce/apex/QuickGiftEntryController.getPaymentChoices';

const mockNavigate = jest.fn();
jest.mock(
  'lightning/navigation',
  () => {
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) =>
      class extends Base {
        [Navigate](...args) {
          mockNavigate(...args);
        }
      };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin, __esModule: true };
  },
  { virtual: true }
);

jest.mock('@salesforce/apex/QuickGiftEntryController.getDefaults', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock('@salesforce/apex/QuickGiftEntryController.saveGift', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock(
  '@salesforce/apex/QuickGiftEntryController.getPaymentChoices',
  () => ({ default: jest.fn() }),
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
  ]
};

const CONTACT_ID = '003000000000000AAA';

function build() {
  const element = createElement('c-quick-gift-entry', { is: QuickGiftEntry });
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

    expect(pick(element, 'form-error').textContent).toContain('Settings are unavailable.');
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

  it('opens the standard new person form and stays on this form after it saves', async () => {
    const element = build();
    await settle();

    pick(element, 'new-person').click();

    const pageReference = mockNavigate.mock.calls[0][0];
    expect(pageReference.type).toBe('standard__objectPage');
    expect(pageReference.attributes).toEqual({ objectApiName: 'Contact', actionName: 'new' });
    expect(pageReference.state.navigationLocation).toBe('RELATED_LIST');
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
    const toast = jest.fn();
    element.addEventListener('lightning__showtoast', toast);

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
        installmentId: null
      }
    });
    expect(pick(element, 'saved')).not.toBeNull();
    expect(pick(element, 'saved-link').href).toContain('/lightning/r/Gift__c/');
    expect(toast).toHaveBeenCalled();
    expect(toast.mock.calls[0][0].detail.messageData[0].label).toBe('G-000123');
    expect(toast.mock.calls[0][0].detail.messageData[0].url).toContain('004000000000000AAA');
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

    expect(pick(element, 'form-error').textContent).toContain('Insufficient access on Gift.');
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
