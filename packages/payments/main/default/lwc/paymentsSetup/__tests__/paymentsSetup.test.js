import { createElement } from 'lwc';
import PaymentsSetup from 'c/paymentsSetup';
import getSetup from '@salesforce/apex/PaymentsSetupController.getSetup';
import saveKeys from '@salesforce/apex/PaymentsSetupController.saveKeys';
import clearKeys from '@salesforce/apex/PaymentsSetupController.clearKeys';

jest.mock('@salesforce/apex/PaymentsSetupController.getSetup', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/PaymentsSetupController.saveKeys', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/PaymentsSetupController.clearKeys', () => ({ default: jest.fn() }), {
  virtual: true
});

const SETUP = {
  processor: 'Stripe',
  mode: 'Test',
  canManage: true,
  receivers: [
    {
      site: 'Payments',
      stripeUrl: 'https://org.my.salesforce-sites.com/services/apexrest/barncrm/payments/v1/stripe',
      payPalUrl: 'https://org.my.salesforce-sites.com/services/apexrest/barncrm/payments/v1/paypal'
    }
  ],
  keys: [
    { name: 'stripeSecretKey', processor: 'Stripe', lastFour: 'a1b2' },
    { name: 'stripeWebhookSecret', processor: 'Stripe', lastFour: null },
    { name: 'payPalClientId', processor: 'PayPal', lastFour: null },
    { name: 'payPalClientSecret', processor: 'PayPal', lastFour: null },
    { name: 'payPalWebhookId', processor: 'PayPal', lastFour: null }
  ]
};

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

async function render(setup) {
  getSetup.mockResolvedValue(setup);
  const element = createElement('c-payments-setup', { is: PaymentsSetup });
  document.body.appendChild(element);
  await flush();
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);
const keyInputs = (element, id) => find(element, id).querySelectorAll('lightning-input');

describe('c-payments-setup', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows the receiver addresses and each key as entered or not, never its value', async () => {
    const element = await render(SETUP);
    const addresses = find(element, 'receivers').querySelectorAll('lightning-input');
    expect(addresses.length).toBe(2);
    expect(addresses[0].value).toContain('/payments/v1/stripe');
    const stripe = keyInputs(element, 'stripe');
    expect(stripe.length).toBe(2);
    expect(stripe[0].type).toBe('password');
    expect(stripe[0].value).toBe('');
    expect(stripe[0].placeholder).toBe('c.Payments_Setup_KeySet');
    expect(keyInputs(element, 'paypal').length).toBe(3);
    expect(find(element, 'no-site')).toBeNull();
    expect(find(element, 'save').disabled).toBe(false);
  });

  it('says there is no Site when there is no address', async () => {
    const element = await render({ ...SETUP, receivers: [] });
    expect(find(element, 'no-site')).not.toBeNull();
    expect(find(element, 'receivers')).toBeNull();
  });

  it('locks the keys for someone who cannot manage settings', async () => {
    const element = await render({ ...SETUP, canManage: false });
    expect(find(element, 'no-manage')).not.toBeNull();
    expect(find(element, 'save').disabled).toBe(true);
    expect(keyInputs(element, 'stripe')[0].disabled).toBe(true);
  });

  it('saves only what was typed and empties the boxes after', async () => {
    const element = await render(SETUP);
    const box = keyInputs(element, 'stripe')[1];
    box.value = 'whsec_new';
    box.dispatchEvent(new CustomEvent('change'));
    saveKeys.mockResolvedValue(SETUP);
    find(element, 'save').click();
    await flush();
    expect(saveKeys).toHaveBeenCalledWith({ keys: { stripeWebhookSecret: 'whsec_new' } });
    expect(find(element, 'saved')).not.toBeNull();
    expect(keyInputs(element, 'stripe')[1].value).toBe('');
  });

  it('clears one processor and shows a refusal', async () => {
    const element = await render(SETUP);
    clearKeys.mockRejectedValue({ body: { message: 'Not allowed.' } });
    find(element, 'clear-paypal').click();
    await flush();
    expect(clearKeys).toHaveBeenCalledWith({ processor: 'PayPal' });
    expect(find(element, 'error').message).toBe('Not allowed.');
  });

  it('shows a general message when the page cannot load', async () => {
    getSetup.mockRejectedValue(new Error('offline'));
    const element = createElement('c-payments-setup', { is: PaymentsSetup });
    document.body.appendChild(element);
    await flush();
    expect(find(element, 'error').message).toBe('c.Payments_Setup_Failed');
  });
});
