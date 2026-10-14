import { createElement } from 'lwc';
import ModuleManager from 'c/moduleManager';
import getState from '@salesforce/apex/ModuleManagerController.getState';
import turnOff from '@salesforce/apex/ModuleManagerController.turnOff';
import turnOn from '@salesforce/apex/ModuleManagerController.turnOn';
import grantAdminAccess from '@salesforce/apex/ModuleManagerController.grantAdminAccess';
import uninstallReport from '@salesforce/apex/ModuleManagerController.uninstallReport';

jest.mock('@salesforce/apex/ModuleManagerController.getState', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ModuleManagerController.turnOff', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ModuleManagerController.turnOn', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/ModuleManagerController.grantAdminAccess',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ModuleManagerController.uninstallReport',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const INSTALLER = '/packaging/installPackage.apexp?p0=04t000000000001AAA';

function state(givingStatus = 'On', canEdit = true) {
  return {
    canEdit,
    modules: [
      { name: 'Core', status: 'On', canSwitch: false, docsUrl: 'https://example.invalid/core' },
      {
        name: 'Giving',
        label: 'BarnCRM Giving',
        appUrl: givingStatus === 'NotInstalled' ? undefined : '/lightning/app/Fundraising',
        status: givingStatus,
        canSwitch: givingStatus !== 'NotInstalled',
        docsUrl: 'https://example.invalid/giving'
      },
      {
        name: 'Volunteers',
        status: 'NotInstalled',
        canSwitch: false,
        docsUrl: 'https://example.invalid/volunteers',
        installUrl: INSTALLER
      },
      {
        name: 'Programs',
        status: 'NotInstalled',
        canSwitch: false,
        docsUrl: 'https://example.invalid/programs'
      }
    ]
  };
}

function settle() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function build() {
  const element = createElement('c-module-manager', { is: ModuleManager });
  document.body.appendChild(element);
  await settle();
  return element;
}

function row(element, name) {
  return element.shadowRoot.querySelector(`li[data-module="${name}"]`);
}

describe('c-module-manager', () => {
  beforeEach(() => {
    getState.mockResolvedValue(state());
    turnOff.mockResolvedValue(state('Off'));
    turnOn.mockResolvedValue(state('On'));
    grantAdminAccess.mockResolvedValue(true);
    uninstallReport.mockResolvedValue([
      { objectLabel: 'Gifts', count: 1204, capped: false },
      { objectLabel: 'Receipts', count: 50000, capped: true }
    ]);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('says what each module is doing', async () => {
    const element = await build();

    expect(row(element, 'Core').textContent).toContain('Core_ModuleManager_StatusOn');
    expect(row(element, 'Volunteers').textContent).toContain(
      'Core_ModuleManager_StatusNotInstalled'
    );
    expect(row(element, 'Core').querySelector('[data-id="turn-off"]')).toBeNull();
  });

  it('names a module by its BarnCRM label and links an installed one to its app', async () => {
    const element = await build();

    const giving = row(element, 'Giving');
    expect(giving.querySelector('[data-id="name"]').textContent).toBe('BarnCRM Giving');
    expect(giving.querySelector('[data-id="open-app"]').getAttribute('href')).toBe(
      '/lightning/app/Fundraising'
    );
    expect(row(element, 'Core').querySelector('[data-id="name"]').textContent).toBe('Core');
    expect(row(element, 'Volunteers').querySelector('[data-id="open-app"]')).toBeNull();
  });

  it('shows no app link for a module that is not installed', async () => {
    getState.mockResolvedValue(state('NotInstalled'));
    const element = await build();

    expect(row(element, 'Giving').querySelector('[data-id="open-app"]')).toBeNull();
  });

  it('links a published module to its installer in a new tab, and says when none is', async () => {
    const element = await build();

    const install = row(element, 'Volunteers').querySelector('[data-id="install"]');
    expect(install.getAttribute('href')).toBe(INSTALLER);
    expect(install.target).toBe('_blank');
    expect(row(element, 'Programs').querySelector('[data-id="no-install-link"]')).not.toBeNull();
  });

  it('turns a module off through Apex', async () => {
    const element = await build();

    row(element, 'Giving').querySelector('[data-id="turn-off"]').click();
    await settle();

    expect(turnOff).toHaveBeenCalledWith({ moduleName: 'Giving' });
    expect(row(element, 'Giving').textContent).toContain('Core_ModuleManager_StatusOff');
    expect(row(element, 'Giving').querySelector('[data-id="turn-on"]')).not.toBeNull();
  });

  it('turns a module on, then gives its admin access in a second call', async () => {
    getState.mockResolvedValue(state('Off'));
    const element = await build();

    row(element, 'Giving').querySelector('[data-id="turn-on"]').click();
    await settle();

    expect(turnOn).toHaveBeenCalledWith({ moduleName: 'Giving' });
    expect(grantAdminAccess).toHaveBeenCalledWith({ moduleName: 'Giving' });
    expect(row(element, 'Giving').textContent).toContain('Core_ModuleManager_StatusOn');
  });

  it('says so when the module is on but its access could not be given', async () => {
    getState.mockResolvedValue(state('Off'));
    grantAdminAccess.mockRejectedValue({ body: { message: 'Access could not be given.' } });
    const element = await build();

    row(element, 'Giving').querySelector('[data-id="turn-on"]').click();
    await settle();

    expect(element.shadowRoot.querySelector('[data-id="error"]').textContent).toContain(
      'Access could not be given.'
    );
  });

  it('shows what an uninstall would delete before linking to Salesforce', async () => {
    const element = await build();

    row(element, 'Giving').querySelector('[data-id="report"]').click();
    await settle();

    expect(uninstallReport).toHaveBeenCalledWith({ moduleName: 'Giving' });
    const panel = row(element, 'Giving').querySelector('[data-id="report-panel"]');
    expect(panel.textContent).toContain('Gifts: 1,204');
    expect(panel.textContent).toContain('Receipts: 50,000+');
    expect(panel.querySelector('[data-id="installed-packages"]').getAttribute('href')).toBe(
      '/lightning/setup/ImportedPackage/home'
    );
  });

  it('checks again for what is installed', async () => {
    const element = await build();

    element.shadowRoot.querySelector('[data-id="check-again"]').click();
    await settle();

    expect(getState).toHaveBeenCalledTimes(2);
  });

  it('lets David read the list without any action', async () => {
    getState.mockResolvedValue(state('On', false));
    const element = await build();

    expect(element.shadowRoot.querySelector('[data-id="read-only"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="turn-off"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="install"]')).toBeNull();
  });

  it('shows a message Maria can act on when a switch fails', async () => {
    turnOff.mockRejectedValue({ body: { message: 'The module could not be switched.' } });
    const element = await build();

    row(element, 'Giving').querySelector('[data-id="turn-off"]').click();
    await settle();

    expect(element.shadowRoot.querySelector('[data-id="error"]').textContent).toContain(
      'The module could not be switched.'
    );
  });
});
