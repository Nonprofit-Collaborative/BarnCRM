import { createElement } from 'lwc';
import HubModules from 'c/hubModules';
import getState from '@salesforce/apex/ModuleManagerController.getState';

jest.mock('@salesforce/apex/ModuleManagerController.getState', () => ({ default: jest.fn() }), {
  virtual: true
});

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

async function build() {
  const element = createElement('c-hub-modules', { is: HubModules });
  document.body.appendChild(element);
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  await new Promise((resolve) => setTimeout(resolve, 0));
  return element;
}

function byId(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

function all(element, id) {
  return Array.from(element.shadowRoot.querySelectorAll(`[data-id="${id}"]`));
}

describe('c-hub-modules', () => {
  afterEach(() => {
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('lists Core alone when no module is installed', async () => {
    getState.mockResolvedValue({
      canEdit: true,
      modules: [
        { name: 'Core', status: 'On', canSwitch: false },
        { name: 'Giving', status: 'NotInstalled', canSwitch: false }
      ]
    });
    const element = await build();

    expect(all(element, 'module-name').map((n) => n.textContent)).toEqual(['Core']);
  });

  it('lists each installed module with its on or off state, and skips the rest', async () => {
    getState.mockResolvedValue({
      canEdit: true,
      modules: [
        { name: 'Core', status: 'On', canSwitch: false },
        { name: 'Giving', status: 'Off', canSwitch: true },
        { name: 'Mirror', status: 'On', canSwitch: true },
        { name: 'Volunteers', status: 'NotInstalled', canSwitch: false }
      ]
    });
    const element = await build();

    expect(all(element, 'module-name').map((n) => n.textContent)).toEqual([
      'Core',
      'Giving',
      'Mirror'
    ]);
    expect(all(element, 'module-status').map((n) => n.textContent)).toEqual([
      'c.Core_ModuleManager_StatusOn',
      'c.Core_ModuleManager_StatusOff',
      'c.Core_ModuleManager_StatusOn'
    ]);
  });

  it('says the list could not load rather than showing an empty list', async () => {
    getState.mockRejectedValue(new Error('nope'));
    const element = await build();

    expect(byId(element, 'load-error')).not.toBeNull();
    expect(all(element, 'module-row')).toHaveLength(0);
  });

  it('names a module by its BarnCRM label when it has one', async () => {
    getState.mockResolvedValue({
      canEdit: true,
      modules: [
        { name: 'Core', status: 'On', canSwitch: false },
        { name: 'Giving', label: 'BarnCRM Giving', status: 'On', canSwitch: true }
      ]
    });
    const element = await build();

    expect(all(element, 'module-name').map((n) => n.textContent)).toEqual([
      'Core',
      'BarnCRM Giving'
    ]);
  });

  it('opens the Modules section of BarnCRM Settings by page reference', async () => {
    getState.mockResolvedValue({ canEdit: true, modules: [] });
    const element = await build();

    byId(element, 'open-manager').click();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'BarnCRM_Settings' },
      state: { c__section: 'Modules' }
    });
  });
});
