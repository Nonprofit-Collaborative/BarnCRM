import { createElement } from 'lwc';
import PaymentsSetup from 'c/paymentsSetup';
import getSetup from '@salesforce/apex/PaymentsSetupController.getSetup';
import saveKeys from '@salesforce/apex/PaymentsSetupController.saveKeys';
import clearKeys from '@salesforce/apex/PaymentsSetupController.clearKeys';
import checkConnection from '@salesforce/apex/PaymentsSetupController.checkConnection';
import scheduleProcessing from '@salesforce/apex/PaymentsSetupController.scheduleProcessing';
import regenerateToken from '@salesforce/apex/PaymentsSetupController.regenerateToken';
import BarnConfirmModal from 'c/barnConfirmModal';

jest.mock(
  '@salesforce/apex/PaymentsSetupController.regenerateToken',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock('@salesforce/apex/PaymentsSetupController.getSetup', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/PaymentsSetupController.saveKeys', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/PaymentsSetupController.clearKeys', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/PaymentsSetupController.checkConnection',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/PaymentsSetupController.scheduleProcessing',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

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
  keys: [{ name: 'payPalWebhookId', processor: 'PayPal', lastFour: null }],
  credentials: [
    {
      processor: 'Stripe',
      connected: true,
      externalCredential: 'Barn_Stripe',
      principal: 'Barn_Stripe_Key',
      parameters: 'SecretKey',
      namedCredentials: 'Barn_Stripe'
    },
    {
      processor: 'PayPal',
      connected: false,
      externalCredential: 'Barn_PayPal',
      principal: 'Barn_PayPal_App',
      parameters: 'ClientId, ClientSecret',
      namedCredentials: 'Barn_PayPal_Live, Barn_PayPal_Sandbox'
    }
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
const inputs = (element, id) => find(element, id).querySelectorAll('lightning-input');

describe('c-payments-setup', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows the addresses, each connection and where its secrets go, with no secret box', async () => {
    const element = await render(SETUP);
    const addresses = find(element, 'receivers').querySelectorAll('lightning-input');
    expect(addresses.length).toBe(2);
    expect(addresses[0].value).toContain('/payments/v1/stripe');
    expect(find(element, 'status-stripe').textContent).toBe('c.Payments_Setup_StatusConnected');
    expect(find(element, 'status-paypal').textContent).toBe('c.Payments_Setup_StatusNotConnected');
    expect(find(element, 'steps-stripe').textContent).toBe('c.Payments_Setup_CredentialSteps');
    expect(inputs(element, 'stripe').length).toBe(0);
    const payPal = inputs(element, 'paypal');
    expect(payPal.length).toBe(1);
    expect(payPal[0].dataset.name).toBe('payPalWebhookId');
    expect(payPal[0].placeholder).toBe('c.Payments_Setup_KeyNotSet');
    expect(find(element, 'no-site')).toBeNull();
    expect(find(element, 'save').disabled).toBe(false);
  });

  it('says there is no Site when there is no address', async () => {
    const element = await render({ ...SETUP, receivers: [] });
    expect(find(element, 'no-site')).not.toBeNull();
    expect(find(element, 'receivers')).toBeNull();
  });

  it('locks every action for someone who cannot manage settings', async () => {
    const element = await render({ ...SETUP, canManage: false });
    expect(find(element, 'no-manage')).not.toBeNull();
    expect(find(element, 'save').disabled).toBe(true);
    expect(find(element, 'check-stripe').disabled).toBe(true);
    expect(inputs(element, 'paypal')[0].disabled).toBe(true);
  });

  it('saves only the webhook id typed and empties the box after', async () => {
    const element = await render(SETUP);
    const box = inputs(element, 'paypal')[0];
    box.value = 'WH-123';
    box.dispatchEvent(new CustomEvent('change'));
    saveKeys.mockResolvedValue(SETUP);
    find(element, 'save').click();
    await flush();
    expect(saveKeys).toHaveBeenCalledWith({ keys: { payPalWebhookId: 'WH-123' } });
    expect(find(element, 'saved').message).toBe('c.Payments_Setup_Saved');
    expect(inputs(element, 'paypal')[0].value).toBe('');
  });

  it('checks a connection and shows what the processor said', async () => {
    const element = await render(SETUP);
    checkConnection.mockResolvedValue({
      ...SETUP,
      checkOk: false,
      checkMessage: 'PayPal could not be reached.'
    });
    find(element, 'check-paypal').click();
    await flush();
    expect(checkConnection).toHaveBeenCalledWith({ processor: 'PayPal' });
    const notice = find(element, 'saved');
    expect(notice.message).toBe('PayPal could not be reached.');
    expect(notice.variant).toBe('warning');
  });

  it('disconnects one processor and shows a refusal', async () => {
    const element = await render(SETUP);
    clearKeys.mockRejectedValue({ body: { message: 'Not allowed.' } });
    BarnConfirmModal.open.mockResolvedValue(true);
    find(element, 'clear-stripe').click();
    await flush();
    expect(clearKeys).toHaveBeenCalledWith({ processor: 'Stripe' });
    expect(find(element, 'error').message).toBe('Not allowed.');
  });

  it('offers Disconnect only where there is something to forget', async () => {
    let element = await render(SETUP);
    expect(find(element, 'clear-stripe')).not.toBeNull();
    expect(find(element, 'clear-paypal')).toBeNull();
    document.body.removeChild(element);
    element = await render({
      ...SETUP,
      keys: [{ name: 'payPalWebhookId', processor: 'PayPal', lastFour: 'AB12' }]
    });
    expect(find(element, 'clear-paypal')).not.toBeNull();
  });

  it('disconnects only after the admin confirms', async () => {
    const element = await render(SETUP);
    BarnConfirmModal.open.mockResolvedValue(false);
    find(element, 'clear-stripe').click();
    await flush();
    expect(BarnConfirmModal.open).toHaveBeenCalledWith(
      expect.objectContaining({ confirmVariant: 'destructive' })
    );
    expect(clearKeys).not.toHaveBeenCalled();
  });

  it('says processing is not scheduled and schedules it on the click', async () => {
    const element = await render(SETUP);
    expect(find(element, 'not-scheduled')).not.toBeNull();
    expect(find(element, 'scheduled')).toBeNull();
    scheduleProcessing.mockResolvedValue({ ...SETUP, scheduled: true });
    find(element, 'schedule').click();
    await flush();
    expect(scheduleProcessing).toHaveBeenCalled();
    expect(find(element, 'scheduled')).not.toBeNull();
    expect(find(element, 'schedule')).toBeNull();
  });

  it('regenerates the token only after the admin confirms', async () => {
    const element = await render(SETUP);
    BarnConfirmModal.open.mockResolvedValue(false);
    find(element, 'regenerate').click();
    await flush();
    expect(regenerateToken).not.toHaveBeenCalled();
    BarnConfirmModal.open.mockResolvedValue(true);
    regenerateToken.mockResolvedValue({
      ...SETUP,
      receivers: [{ ...SETUP.receivers[0], stripeUrl: 'https://new/stripe?token=b' }]
    });
    find(element, 'regenerate').click();
    await flush();
    expect(BarnConfirmModal.open).toHaveBeenCalledWith(
      expect.objectContaining({ confirmVariant: 'destructive' })
    );
    expect(regenerateToken).toHaveBeenCalledTimes(1);
    expect(inputs(element, 'receivers')[0].value).toContain('token=b');
  });

  it('shows a general message when the page cannot load', async () => {
    getSetup.mockRejectedValue(new Error('offline'));
    const element = createElement('c-payments-setup', { is: PaymentsSetup });
    document.body.appendChild(element);
    await flush();
    expect(find(element, 'error').message).toBe('c.Payments_Setup_Failed');
  });
});
