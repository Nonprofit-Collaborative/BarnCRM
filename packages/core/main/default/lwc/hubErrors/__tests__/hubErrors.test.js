import { createElement } from 'lwc';
import HubErrors from 'c/hubErrors';
import getHomeModel from '@salesforce/apex/HubController.getHomeModel';
import countInstallProblems from '@salesforce/apex/CorePostInstall.countInstallProblems';

jest.mock(
  '@salesforce/apex/HubController.getHomeModel',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/CorePostInstall.countInstallProblems',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
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

function build() {
  const element = createElement('c-hub-errors', { is: HubErrors });
  document.body.appendChild(element);
  return element;
}

function settle() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function byId(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

describe('c-hub-errors', () => {
  afterEach(() => {
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('counts errors to review and opens the new errors list by page reference', async () => {
    const element = build();
    getHomeModel.emit({ newErrorCount: 3 });
    await settle();

    expect(byId(element, 'error-count').textContent).toBe('3');
    byId(element, 'open-error-log').click();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__objectPage',
      attributes: { objectApiName: 'Error_Log__c', actionName: 'list' },
      state: { filterName: 'New_Errors' }
    });
  });

  it('says the cap with a plus when there are more errors than the tile counts', async () => {
    const element = build();
    getHomeModel.emit({ newErrorCount: 999, newErrorCountCapped: true });
    await settle();

    expect(byId(element, 'error-count').textContent).toBe('999+');
  });

  it('says the tile could not load rather than showing zero', async () => {
    const element = build();
    getHomeModel.error();
    await settle();

    expect(byId(element, 'error-count')).toBeNull();
    expect(byId(element, 'load-error').textContent).toContain('Core_HubHome_LoadErrorMessage');
  });

  it('says setup completed when the install logged nothing', async () => {
    const element = build();
    countInstallProblems.emit(0);
    await settle();

    const status = byId(element, 'install-status');
    expect(status.textContent).toContain('Core_HubHome_InstallCompleted');
    expect(status.querySelector('lightning-icon')).toBeNull();
  });

  it('says setup had problems when the install logged some, and not by color alone', async () => {
    const element = build();
    countInstallProblems.emit(2);
    await settle();

    const status = byId(element, 'install-status');
    expect(status.textContent).toContain('Core_HubHome_InstallProblems');
    expect(status.getAttribute('aria-live')).toBe('polite');
    const icon = status.querySelector('lightning-icon');
    expect(icon.alternativeText).toBe('c.Core_HubHome_WarningAltText');
  });

  it('says nothing about the install to someone who cannot read the Error Log', async () => {
    const element = build();
    countInstallProblems.emit(null);
    await settle();

    expect(byId(element, 'install-status')).toBeNull();
  });

  it('still shows the count when the install count cannot be read', async () => {
    const element = build();
    getHomeModel.emit({ newErrorCount: 0 });
    countInstallProblems.error();
    await settle();

    expect(byId(element, 'install-status')).toBeNull();
    expect(byId(element, 'error-count').textContent).toBe('0');
  });
});
