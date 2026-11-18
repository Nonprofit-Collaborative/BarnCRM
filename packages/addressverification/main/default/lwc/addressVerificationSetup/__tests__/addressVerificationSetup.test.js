import { createElement } from 'lwc';
import AddressVerificationSetup from 'c/addressVerificationSetup';
import getSetup from '@salesforce/apex/AddressVerificationController.getSetup';
import checkConnection from '@salesforce/apex/AddressVerificationController.checkConnection';
import clearKeys from '@salesforce/apex/AddressVerificationController.clearKeys';
import verifyWaiting from '@salesforce/apex/AddressVerificationController.verifyWaiting';

jest.mock(
  '@salesforce/apex/AddressVerificationController.getSetup',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/AddressVerificationController.checkConnection',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/AddressVerificationController.clearKeys',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/AddressVerificationController.verifyWaiting',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const credentials = (smartyConnected) => [
  {
    provider: 'Smarty',
    connected: smartyConnected,
    externalCredential: 'Barn_Smarty',
    principal: 'Barn_Smarty_Key',
    parameters: 'AuthId, AuthToken'
  },
  {
    provider: 'Google',
    connected: false,
    externalCredential: 'Barn_Google_Address',
    principal: 'Barn_Google_Address_Key',
    parameters: 'ApiKey'
  }
];

const SETUP = {
  provider: 'Smarty',
  ready: true,
  canManage: true,
  credentials: credentials(true)
};

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

async function render(setup) {
  getSetup.mockResolvedValue(setup);
  const element = createElement('c-address-verification-setup', {
    is: AddressVerificationSetup
  });
  document.body.appendChild(element);
  await flush();
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-address-verification-setup', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows each provider connected or not and where its key goes, with no key box', async () => {
    const element = await render(SETUP);
    expect(find(element, 'status-smarty').textContent).toBe(
      'c.AddressVerification_Setup_StatusConnected'
    );
    expect(find(element, 'status-google').textContent).toBe(
      'c.AddressVerification_Setup_StatusNotConnected'
    );
    expect(find(element, 'steps-google').textContent).toBe(
      'c.AddressVerification_Setup_CredentialSteps'
    );
    expect(element.shadowRoot.querySelectorAll('lightning-input').length).toBe(0);
    expect(find(element, 'verify').disabled).toBe(false);
  });

  it('locks everything for someone who cannot manage settings', async () => {
    const element = await render({ ...SETUP, canManage: false });
    expect(find(element, 'no-manage')).not.toBeNull();
    expect(find(element, 'check-smarty').disabled).toBe(true);
    expect(find(element, 'verify').disabled).toBe(true);
  });

  it('cannot start a check before the provider is connected', async () => {
    const element = await render({ ...SETUP, ready: false });
    expect(find(element, 'verify').disabled).toBe(true);
  });

  it('checks a connection, shows what was found and reloads the status', async () => {
    const element = await render({ ...SETUP, ready: false, credentials: credentials(false) });
    checkConnection.mockResolvedValue('Smarty is connected.');
    getSetup.mockResolvedValue(SETUP);
    find(element, 'check-smarty').click();
    await flush();
    expect(checkConnection).toHaveBeenCalledWith({ provider: 'Smarty' });
    const message = find(element, 'message');
    expect(message.message).toBe('Smarty is connected.');
    expect(message.variant).toBe('success');
    expect(find(element, 'status-smarty').textContent).toBe(
      'c.AddressVerification_Setup_StatusConnected'
    );
  });

  it('says plainly when a check fails', async () => {
    const element = await render({ ...SETUP, credentials: credentials(false) });
    checkConnection.mockResolvedValue('Google could not be reached.');
    getSetup.mockResolvedValue({ ...SETUP, credentials: credentials(false) });
    find(element, 'check-google').click();
    await flush();
    expect(find(element, 'message').variant).toBe('warning');
  });

  it('disconnects one provider and shows a refusal', async () => {
    const element = await render(SETUP);
    clearKeys.mockRejectedValue({ body: { message: 'Not allowed.' } });
    find(element, 'clear-smarty').click();
    await flush();
    expect(clearKeys).toHaveBeenCalledWith({ provider: 'Smarty' });
    expect(find(element, 'error').message).toBe('Not allowed.');
  });

  it('starts the check of waiting addresses and shows what happened', async () => {
    const element = await render(SETUP);
    verifyWaiting.mockResolvedValue('Started.');
    find(element, 'verify').click();
    await flush();
    expect(verifyWaiting).toHaveBeenCalled();
    expect(find(element, 'message').message).toBe('Started.');
  });

  it('shows a general message when the page cannot load', async () => {
    getSetup.mockRejectedValue(new Error('offline'));
    const element = createElement('c-address-verification-setup', {
      is: AddressVerificationSetup
    });
    document.body.appendChild(element);
    await flush();
    expect(find(element, 'error').message).toBe('c.AddressVerification_Setup_Failed');
  });
});
