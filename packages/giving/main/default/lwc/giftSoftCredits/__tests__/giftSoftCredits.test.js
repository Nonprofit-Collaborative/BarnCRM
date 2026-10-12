import { createElement } from 'lwc';
import GiftSoftCredits from 'c/giftSoftCredits';
import getCredits from '@salesforce/apex/SoftCreditController.getCredits';
import addCredit from '@salesforce/apex/SoftCreditController.addCredit';
import removeCredit from '@salesforce/apex/SoftCreditController.removeCredit';

jest.mock(
  '@salesforce/apex/SoftCreditController.getCredits',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock('@salesforce/apex/SoftCreditController.addCredit', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock('@salesforce/apex/SoftCreditController.removeCredit', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock('@salesforce/apex', () => ({ refreshApex: jest.fn(() => Promise.resolve()) }), {
  virtual: true
});

jest.mock('@salesforce/label/c.Giving_SoftCredits_Empty', () => ({ default: 'Nobody yet.' }), {
  virtual: true
});

jest.mock(
  '@salesforce/label/c.Giving_SoftCredits_AutomaticBadge',
  () => ({ default: 'Automatic' }),
  {
    virtual: true
  }
);

const GIFT_ID = 'a02000000000001AAA';

const LUIS = {
  recordId: 'a03000000000001AAA',
  name: 'SC-000001',
  personId: '003000000000002AAA',
  personName: 'Luis Garcia',
  role: 'Household Member',
  customRole: null,
  amount: 500,
  percent: 100,
  isAutomatic: true
};

const SOLICITOR = {
  recordId: 'a03000000000002AAA',
  name: 'SC-000002',
  personId: '003000000000003AAA',
  personName: 'Tom Alvarez',
  role: 'Solicitor',
  customRole: null,
  amount: 500,
  percent: 100,
  isAutomatic: false
};

const PANEL = { credits: [LUIS, SOLICITOR], canAdd: true, canRemove: true };

function createComponent() {
  const element = createElement('c-gift-soft-credits', { is: GiftSoftCredits });
  element.recordId = GIFT_ID;
  document.body.appendChild(element);
  return element;
}

function flush() {
  return Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());
}

describe('c-gift-soft-credits', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists every credit with its role and amount', async () => {
    const element = createComponent();
    getCredits.emit(PANEL);
    await flush();

    const items = element.shadowRoot.querySelectorAll('[data-id="credit-list"] li');
    expect(items.length).toBe(2);
    expect(items[0].textContent).toContain('Luis Garcia');
    expect(items[0].textContent).toContain('Household Member');
  });

  it('badges the credit BarnCRM created and offers no remove button for it', async () => {
    const element = createComponent();
    getCredits.emit(PANEL);
    await flush();

    expect(element.shadowRoot.querySelectorAll('.automatic-badge').length).toBe(1);
    const removeButtons = element.shadowRoot.querySelectorAll('.remove-button');
    expect(removeButtons.length).toBe(1);
    expect(removeButtons[0].dataset.credit).toBe(SOLICITOR.recordId);
  });

  it('says so when nobody else is recognized', async () => {
    const element = createComponent();
    getCredits.emit({ credits: [], canAdd: true, canRemove: true });
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="empty-state"]').textContent).toBe(
      'Nobody yet.'
    );
  });

  it('adds a credit a person entered', async () => {
    addCredit.mockResolvedValue(PANEL);
    const element = createComponent();
    getCredits.emit({ credits: [LUIS], canAdd: true, canRemove: true });
    await flush();

    element.shadowRoot.querySelector('[data-id="add-button"]').click();
    await flush();

    element.shadowRoot
      .querySelector('[data-id="person-picker"]')
      .dispatchEvent(new CustomEvent('change', { detail: { recordId: SOLICITOR.personId } }));
    element.shadowRoot
      .querySelector('[data-id="role-input"]')
      .dispatchEvent(new CustomEvent('change', { detail: { value: 'Solicitor' } }));
    element.shadowRoot
      .querySelector('[data-id="amount-input"]')
      .dispatchEvent(new CustomEvent('change', { detail: { value: 500 } }));
    await flush();

    element.shadowRoot.querySelector('[data-id="save-button"]').click();
    await flush();

    expect(addCredit).toHaveBeenCalledWith({
      giftId: GIFT_ID,
      personId: SOLICITOR.personId,
      role: 'Solicitor',
      customRole: undefined,
      amount: 500
    });
    expect(element.shadowRoot.querySelector('[data-id="add-form"]')).toBeNull();
  });

  it('will not save until a person is chosen', async () => {
    const element = createComponent();
    getCredits.emit(PANEL);
    await flush();

    element.shadowRoot.querySelector('[data-id="add-button"]').click();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="save-button"]').disabled).toBe(true);
  });

  it('removes a credit a person entered', async () => {
    removeCredit.mockResolvedValue({ credits: [LUIS], canAdd: true, canRemove: true });
    const element = createComponent();
    getCredits.emit(PANEL);
    await flush();

    element.shadowRoot.querySelector('.remove-button').click();
    await flush();

    expect(removeCredit).toHaveBeenCalledWith({ softCreditId: SOLICITOR.recordId });
    expect(element.shadowRoot.querySelectorAll('[data-id="credit-list"] li').length).toBe(1);
  });

  it('shows the message the server sends when an action is refused', async () => {
    removeCredit.mockRejectedValue({
      body: { message: 'BarnCRM created this credit and keeps it up to date.' }
    });
    const element = createComponent();
    getCredits.emit(PANEL);
    await flush();

    element.shadowRoot.querySelector('.remove-button').click();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error-message"]').textContent.trim()).toBe(
      'BarnCRM created this credit and keeps it up to date.'
    );
  });

  it('disables adding for a person who may only read', async () => {
    const element = createComponent();
    getCredits.emit({ credits: [LUIS], canAdd: false, canRemove: false });
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="add-button"]').disabled).toBe(true);
    expect(element.shadowRoot.querySelectorAll('.remove-button').length).toBe(0);
  });

  it('reports a failure to load the panel', async () => {
    const element = createComponent();
    getCredits.error({ message: 'You do not have access to soft credits.' });
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error-message"]')).not.toBeNull();
  });
});
