import { createElement } from 'lwc';
import AddressPanel from 'c/addressPanel';
import getAddresses from '@salesforce/apex/AddressController.getAddresses';
import setDefault from '@salesforce/apex/AddressController.setDefault';

jest.mock(
  '@salesforce/apex/AddressController.getAddresses',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock('@salesforce/apex/AddressController.setDefault', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock('@salesforce/apex', () => ({ refreshApex: jest.fn() }), { virtual: true });

const HOME = {
  id: 'a0100000000000AAAA',
  addressNumber: 'AD-000001',
  addressType: 'Home',
  street: '812 Willow Lane',
  city: 'Springfield',
  state: 'IL',
  postalCode: '62704',
  country: 'United States',
  isDefault: true,
  isSeasonal: false,
  seasonalStart: null,
  seasonalEnd: null
};

const WINTER = {
  id: 'a0100000000000BBBB',
  addressNumber: 'AD-000002',
  addressType: 'Seasonal',
  street: '4120 East Camelback Road',
  city: 'Phoenix',
  state: 'AZ',
  postalCode: '85018',
  country: 'United States',
  isDefault: false,
  isSeasonal: true,
  seasonalStart: 'January 1',
  seasonalEnd: 'March 31'
};

function build(objectApiName = 'Account') {
  const element = createElement('c-address-panel', { is: AddressPanel });
  element.recordId = '0011000000000001AA';
  element.objectApiName = objectApiName;
  document.body.appendChild(element);
  return element;
}

function flush() {
  return Promise.resolve().then(() => Promise.resolve());
}

describe('c-address-panel', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows a card for every address on file', async () => {
    const element = build();
    getAddresses.emit([HOME, WINTER]);
    await flush();

    const cards = element.shadowRoot.querySelectorAll('[data-id="address-card"]');
    expect(cards.length).toBe(2);
    const streets = Array.from(
      element.shadowRoot.querySelectorAll('[data-id="address-street"]')
    ).map((node) => node.textContent);
    expect(streets).toEqual(['812 Willow Lane', '4120 East Camelback Road']);
  });

  it('badges the address in use and offers to move the badge to the others', async () => {
    const element = build();
    getAddresses.emit([HOME, WINTER]);
    await flush();

    expect(element.shadowRoot.querySelectorAll('[data-id="default-badge"]').length).toBe(1);
    const buttons = element.shadowRoot.querySelectorAll('.set-default');
    expect(buttons.length).toBe(1);
    expect(buttons[0].dataset.id).toBe(WINTER.id);
  });

  it('reads the seasonal range as dates rather than numbers', async () => {
    const element = build();
    getAddresses.emit([WINTER]);
    await flush();

    const seasonal = element.shadowRoot.querySelector('[data-id="address-seasonal"]');
    expect(seasonal.textContent).toContain('January 1');
    expect(seasonal.textContent).toContain('March 31');
  });

  it('says so when the household has no addresses yet', async () => {
    const element = build();
    getAddresses.emit([]);
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="empty"]')).not.toBeNull();
    expect(element.shadowRoot.querySelectorAll('[data-id="address-card"]').length).toBe(0);
  });

  it('shows a message when the addresses cannot be read', async () => {
    const element = build();
    getAddresses.error();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="empty"]')).toBeNull();
  });

  it('moves the badge when an address is set as the default', async () => {
    setDefault.mockResolvedValue([
      { ...WINTER, isDefault: true },
      { ...HOME, isDefault: false }
    ]);
    const element = build();
    getAddresses.emit([HOME, WINTER]);
    await flush();

    element.shadowRoot.querySelector('.set-default').click();
    await flush();

    expect(setDefault).toHaveBeenCalledWith({ addressId: WINTER.id });
    const badged = element.shadowRoot.querySelectorAll('[data-id="default-badge"]');
    expect(badged.length).toBe(1);
    const buttons = element.shadowRoot.querySelectorAll('.set-default');
    expect(buttons[0].dataset.id).toBe(HOME.id);
  });

  it('shows a message when the default could not be changed', async () => {
    setDefault.mockRejectedValue(new Error('no'));
    const element = build();
    getAddresses.emit([HOME, WINTER]);
    await flush();

    element.shadowRoot.querySelector('.set-default').click();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error"]')).not.toBeNull();
  });

  it('opens and closes the new address form', async () => {
    const element = build();
    getAddresses.emit([HOME]);
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="add-form"]')).toBeNull();
    element.shadowRoot.querySelector('[data-id="add-address"]').click();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="add-form"]')).not.toBeNull();

    element.shadowRoot.querySelector('[data-id="cancel"]').click();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="add-form"]')).toBeNull();
  });

  it('ties a new address to the household when it sits on an account', async () => {
    const element = build('Account');
    getAddresses.emit([HOME]);
    await flush();
    element.shadowRoot.querySelector('[data-id="add-address"]').click();
    await flush();

    const owner = element.shadowRoot.querySelector('lightning-input-field');
    expect(owner.fieldName).toBe('Account__c');
    expect(owner.value).toBe('0011000000000001AA');
  });

  it('ties a new address to the person when it sits on a contact', async () => {
    const element = build('Contact');
    getAddresses.emit([HOME]);
    await flush();
    element.shadowRoot.querySelector('[data-id="add-address"]').click();
    await flush();

    const owner = element.shadowRoot.querySelector('lightning-input-field');
    expect(owner.fieldName).toBe('Contact__c');
  });

  it('saves the first address as the one in use', async () => {
    const element = build('Account');
    getAddresses.emit([]);
    await flush();
    element.shadowRoot.querySelector('[data-id="add-address"]').click();
    await flush();

    const flag = element.shadowRoot.querySelector('[data-id="first-address-default"]');
    expect(flag.fieldName).toBe('Is_Default__c');
    expect(flag.value).toBe(true);
  });

  it('leaves the default alone when the record already has addresses', async () => {
    const element = build('Account');
    getAddresses.emit([HOME]);
    await flush();
    element.shadowRoot.querySelector('[data-id="add-address"]').click();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="first-address-default"]')).toBeNull();
  });

  it('does not guess the first address when the list could not be read', async () => {
    const element = build('Account');
    getAddresses.error({ body: { message: 'boom' } });
    await flush();
    const add = element.shadowRoot.querySelector('[data-id="add-address"]');
    if (add) {
      add.click();
      await flush();
    }

    expect(element.shadowRoot.querySelector('[data-id="first-address-default"]')).toBeNull();
  });

  it('closes the form and refreshes after a new address is saved', async () => {
    const element = build();
    getAddresses.emit([HOME]);
    await flush();
    element.shadowRoot.querySelector('[data-id="add-address"]').click();
    await flush();

    const form = element.shadowRoot.querySelector('lightning-record-edit-form');
    form.dispatchEvent(new CustomEvent('success'));
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="add-form"]')).toBeNull();
  });
});
