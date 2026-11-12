import { createElement } from 'lwc';
import AddressVerificationSetup from 'c/addressVerificationSetup';
import getSetup from '@salesforce/apex/AddressVerificationController.getSetup';
import saveKeys from '@salesforce/apex/AddressVerificationController.saveKeys';
import clearKeys from '@salesforce/apex/AddressVerificationController.clearKeys';
import verifyWaiting from '@salesforce/apex/AddressVerificationController.verifyWaiting';

jest.mock(
  '@salesforce/apex/AddressVerificationController.getSetup',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/AddressVerificationController.saveKeys',
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

const SETUP = {
  provider: 'Smarty',
  ready: true,
  canManage: true,
  keys: [
    { name: 'smartyAuthId', provider: 'Smarty', lastFour: 'a1b2' },
    { name: 'smartyAuthToken', provider: 'Smarty', lastFour: 'c3d4' },
    { name: 'googleApiKey', provider: 'Google', lastFour: null }
  ]
};

const flush = () =>
  Promise.resolve()
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
const keyInputs = (element, id) => find(element, id).querySelectorAll('lightning-input');

describe('c-address-verification-setup', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows each key as entered or not, never its value', async () => {
    const element = await render(SETUP);
    const smarty = keyInputs(element, 'smarty');
    expect(smarty.length).toBe(2);
    expect(smarty[0].type).toBe('password');
    expect(smarty[0].value).toBe('');
    expect(smarty[0].placeholder).toBe('c.AddressVerification_Setup_KeySet');
    expect(keyInputs(element, 'google')[0].placeholder).toBe(
      'c.AddressVerification_Setup_KeyNotSet'
    );
    expect(find(element, 'verify').disabled).toBe(false);
  });

  it('locks everything for someone who cannot manage settings', async () => {
    const element = await render({ ...SETUP, canManage: false });
    expect(find(element, 'no-manage')).not.toBeNull();
    expect(find(element, 'save').disabled).toBe(true);
    expect(find(element, 'verify').disabled).toBe(true);
  });

  it('cannot start a check before the keys are entered', async () => {
    const element = await render({ ...SETUP, ready: false });
    expect(find(element, 'verify').disabled).toBe(true);
  });

  it('saves only what was typed and empties the boxes after', async () => {
    const element = await render(SETUP);
    const box = keyInputs(element, 'google')[0];
    box.value = 'AIza-new';
    box.dispatchEvent(new CustomEvent('change'));
    saveKeys.mockResolvedValue(SETUP);
    find(element, 'save').click();
    await flush();
    expect(saveKeys).toHaveBeenCalledWith({ keys: { googleApiKey: 'AIza-new' } });
    expect(find(element, 'message').message).toBe('c.AddressVerification_Setup_Saved');
    expect(keyInputs(element, 'google')[0].value).toBe('');
  });

  it('clears one provider and shows a refusal', async () => {
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
