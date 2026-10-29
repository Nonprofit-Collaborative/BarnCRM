import { createElement } from 'lwc';
import FirstRunSetup from 'c/firstRunSetup';
import FirstRunModal from 'c/firstRunModal';
import getState from '@salesforce/apex/FirstRunController.getState';

// A namespaced org answers with qualified names; the component writes none of its own.
jest.mock(
  '@salesforce/apex/SettingsController.getSettingsLink',
  () => ({
    default: jest.fn(() =>
      Promise.resolve({ tabApiName: 'ns__BarnCRM_Settings', sectionKey: 'ns__section' })
    )
  }),
  { virtual: true }
);

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
    return { NavigationMixin, CurrentPageReference: null, __esModule: true };
  },
  { virtual: true }
);
jest.mock('@salesforce/apex/FirstRunController.getState', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FirstRunController.finish', () => ({ default: jest.fn() }), {
  virtual: true
});

const ADMIN_STATE = {
  needsSetup: true,
  canFinish: true,
  recommendedSuite: 'Standard',
  features: []
};

function settle() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function build() {
  const element = createElement('c-first-run-setup', { is: FirstRunSetup });
  document.body.appendChild(element);
  await settle();
  return element;
}

describe('c-first-run-setup', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('opens nothing once setup is finished', async () => {
    getState.mockResolvedValue({ needsSetup: false, canFinish: true, features: [] });
    await build();

    expect(FirstRunModal.open).not.toHaveBeenCalled();
  });

  it('blocks nothing when the state cannot be read, and says so', async () => {
    getState.mockRejectedValue({ body: { message: 'nope' } });
    const element = await build();

    expect(FirstRunModal.open).not.toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('[data-id="load-error"]').textContent).toBe('nope');
  });

  it('opens the setup window with the state it read, closable only by finishing', async () => {
    getState.mockResolvedValue(ADMIN_STATE);
    FirstRunModal.open.mockResolvedValue(undefined);
    await build();

    expect(FirstRunModal.open).toHaveBeenCalledWith({
      size: 'small',
      label: 'c.Core_FirstRun_Title',
      state: ADMIN_STATE,
      disableClose: true
    });
    expect(mockNavigate).not.toHaveBeenCalled();
  });

  it('lets someone who cannot finish setup close the window', async () => {
    const state = { ...ADMIN_STATE, canFinish: false };
    getState.mockResolvedValue(state);
    FirstRunModal.open.mockResolvedValue(undefined);
    await build();

    expect(FirstRunModal.open).toHaveBeenCalledWith(
      expect.objectContaining({ state, disableClose: false })
    );
    expect(mockNavigate).not.toHaveBeenCalled();
  });

  it('refreshes the page and lands on General once setup is finished', async () => {
    getState.mockResolvedValue(ADMIN_STATE);
    FirstRunModal.open.mockResolvedValue({ finished: true });
    const finished = jest.fn();
    const refreshed = jest.fn();
    document.body.addEventListener('lightning__refresh', refreshed);
    const element = createElement('c-first-run-setup', { is: FirstRunSetup });
    element.addEventListener('setupfinished', finished);
    document.body.appendChild(element);
    await settle();

    expect(finished).toHaveBeenCalledTimes(1);
    expect(refreshed).toHaveBeenCalledTimes(1);
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'ns__BarnCRM_Settings' },
      state: { ns__section: 'General' }
    });
    document.body.removeEventListener('lightning__refresh', refreshed);
  });
});
