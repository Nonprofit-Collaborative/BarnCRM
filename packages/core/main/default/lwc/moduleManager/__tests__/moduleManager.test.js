import { createElement } from 'lwc';
import ModuleManager from 'c/moduleManager';
import getState from '@salesforce/apex/ModuleManagerController.getState';
import turnOff from '@salesforce/apex/ModuleManagerController.turnOff';
import turnOn from '@salesforce/apex/ModuleManagerController.turnOn';
import grantAdminAccess from '@salesforce/apex/ModuleManagerController.grantAdminAccess';
import uninstallReport from '@salesforce/apex/ModuleManagerController.uninstallReport';
import saveShowNonprofitModules from '@salesforce/apex/ModuleManagerController.saveShowNonprofitModules';
import finishSetup from '@salesforce/apex/ModuleManagerController.finishSetup';

jest.mock('@salesforce/apex/ModuleManagerController.finishSetup', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock('@salesforce/apex/ModuleManagerController.getState', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/ModuleManagerController.saveShowNonprofitModules',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
// The hidden-count line carries a placeholder, so this label needs its text to assert the count.
jest.mock(
  '@salesforce/label/c.Core_ModuleManager_NonprofitHidden',
  () => ({ default: 'Installed nonprofit modules hidden: {0}' }),
  { virtual: true }
);
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

// The same list with the catalog's nonprofit-only modules flagged: Giving installed, Volunteers
// and Programs not.
function nonprofitState(show = true, canEdit = true) {
  const base = state('On', canEdit);
  return {
    ...base,
    showNonprofitModules: show,
    modules: base.modules.map((module) => ({
      ...module,
      nonprofitOnly: module.name !== 'Core'
    }))
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

  it('says nothing about other rollup tools when the org has none', async () => {
    const element = await build();

    expect(element.shadowRoot.querySelector('[data-id="other-rollup-tools"]')).toBeNull();
  });

  it('names DLRS as a separate rollup tool when the page is told it is here', async () => {
    getState.mockResolvedValue({ ...state(), otherRollupTools: ['This org also runs DLRS.'] });
    const element = await build();

    const notice = element.shadowRoot.querySelector('[data-id="other-rollup-tools"]');
    expect(notice.textContent).toContain('Core_OtherRollupTools_Title');
    expect(notice.textContent).toContain('This org also runs DLRS.');
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

  it('says which modules to install first for one that needs them', async () => {
    const needing = state('NotInstalled');
    needing.modules[1].installFirst = 'BarnCRM Rollup Builder';
    getState.mockResolvedValue(needing);
    const element = await build();

    expect(row(element, 'Giving').querySelector('[data-id="install-first"]')).not.toBeNull();
    expect(row(element, 'Volunteers').querySelector('[data-id="install-first"]')).toBeNull();
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

  describe('nonprofit modules section', () => {
    function names(group) {
      return Array.from(group.querySelectorAll('li[data-module]')).map((li) => li.dataset.module);
    }

    it('lists the other modules first and the nonprofit ones in a section at the bottom', async () => {
      getState.mockResolvedValue(nonprofitState());
      const element = await build();

      const groups = Array.from(element.shadowRoot.querySelectorAll('[data-group]'));
      expect(groups.map((group) => group.dataset.group)).toEqual(['general', 'nonprofit']);
      expect(names(groups[0])).toEqual(['Core']);
      expect(names(groups[1])).toEqual(['Giving', 'Volunteers', 'Programs']);
      expect(groups[1].querySelector('[data-id="nonprofit-title"]').textContent).toContain(
        'Core_ModuleManager_NonprofitTitle'
      );
    });

    it('has Show Nonprofit Modules checked by default', async () => {
      getState.mockResolvedValue(nonprofitState());
      const element = await build();

      const box = element.shadowRoot.querySelector('[data-id="show-nonprofit"]');
      expect(box.label).toContain('Core_ModuleManager_ShowNonprofit');
      expect(box.checked).toBe(true);
      expect(element.shadowRoot.querySelector('[data-id="nonprofit-hidden"]')).toBeNull();
    });

    it('treats a missing saved value as checked', async () => {
      const missing = nonprofitState();
      delete missing.showNonprofitModules;
      getState.mockResolvedValue(missing);
      const element = await build();

      expect(element.shadowRoot.querySelector('[data-id="show-nonprofit"]').checked).toBe(true);
      expect(row(element, 'Giving')).not.toBeNull();
    });

    it('saves the choice through Apex and hides the nonprofit modules when cleared', async () => {
      getState.mockResolvedValue(nonprofitState());
      saveShowNonprofitModules.mockResolvedValue(nonprofitState(false));
      const element = await build();

      const box = element.shadowRoot.querySelector('[data-id="show-nonprofit"]');
      box.checked = false;
      box.dispatchEvent(new CustomEvent('change'));
      await settle();

      expect(saveShowNonprofitModules).toHaveBeenCalledWith({ show: false });
      expect(row(element, 'Core')).not.toBeNull();
      expect(row(element, 'Giving')).toBeNull();
      expect(row(element, 'Volunteers')).toBeNull();
      // The checkbox stays so the choice can be undone.
      expect(element.shadowRoot.querySelector('[data-id="show-nonprofit"]').checked).toBe(false);
    });

    it('says how many installed nonprofit modules are hidden', async () => {
      getState.mockResolvedValue(nonprofitState(false));
      const element = await build();

      // Giving is installed; Volunteers and Programs are not.
      expect(
        element.shadowRoot.querySelector('[data-id="nonprofit-hidden"]').textContent
      ).toContain('Installed nonprofit modules hidden: 1');
    });

    it('gives no hidden cue when none of the hidden modules is installed', async () => {
      const none = nonprofitState(false);
      none.modules[1].status = 'NotInstalled';
      getState.mockResolvedValue(none);
      const element = await build();

      expect(element.shadowRoot.querySelector('[data-id="nonprofit-hidden"]')).toBeNull();
      expect(element.shadowRoot.querySelector('[data-id="show-nonprofit"]')).not.toBeNull();
    });

    it('shows the rows again when ticked', async () => {
      getState.mockResolvedValue(nonprofitState(false));
      saveShowNonprofitModules.mockResolvedValue(nonprofitState(true));
      const element = await build();

      const box = element.shadowRoot.querySelector('[data-id="show-nonprofit"]');
      box.checked = true;
      box.dispatchEvent(new CustomEvent('change'));
      await settle();

      expect(saveShowNonprofitModules).toHaveBeenCalledWith({ show: true });
      expect(row(element, 'Giving')).not.toBeNull();
    });

    it('puts the checkbox back and shows the error when the save fails', async () => {
      getState.mockResolvedValue(nonprofitState());
      saveShowNonprofitModules.mockRejectedValue({ body: { message: 'Not allowed.' } });
      const element = await build();

      const box = element.shadowRoot.querySelector('[data-id="show-nonprofit"]');
      box.checked = false;
      box.dispatchEvent(new CustomEvent('change'));
      await settle();

      expect(element.shadowRoot.querySelector('[data-id="error"]').textContent).toContain(
        'Not allowed.'
      );
      expect(element.shadowRoot.querySelector('[data-id="show-nonprofit"]').checked).toBe(true);
      expect(row(element, 'Giving')).not.toBeNull();
    });

    it('disables the checkbox for someone who can only read', async () => {
      getState.mockResolvedValue(nonprofitState(true, false));
      const element = await build();

      expect(element.shadowRoot.querySelector('[data-id="show-nonprofit"]').disabled).toBe(true);
    });

    it('shows no section when no module is nonprofit-only', async () => {
      const element = await build();

      expect(element.shadowRoot.querySelector('[data-id="show-nonprofit"]')).toBeNull();
      expect(element.shadowRoot.querySelector('[data-group="nonprofit"]')).toBeNull();
    });
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

  describe('Finish Setup (FS1)', () => {
    function setupNotRun(canEdit = true) {
      const base = state('On', canEdit);
      return {
        ...base,
        modules: base.modules.map((module) => ({
          ...module,
          setupPending: module.name === 'Giving'
        }))
      };
    }

    it('flags a module whose setup never ran and offers Finish Setup', async () => {
      getState.mockResolvedValue(setupNotRun());
      const element = await build();

      const giving = row(element, 'Giving');
      expect(giving.querySelector('[data-id="setup-not-run"]').textContent).toContain(
        'Core_ModuleSetup_NotRunNotice'
      );
      const button = giving.querySelector('[data-id="finish-setup"]');
      expect(button.label).toBe('c.Core_ModuleSetup_FinishButton');
      expect(row(element, 'Core').querySelector('[data-id="setup-not-run"]')).toBeNull();
      expect(row(element, 'Core').querySelector('[data-id="finish-setup"]')).toBeNull();
    });

    it('runs the setup steps through Apex and clears the notice', async () => {
      getState.mockResolvedValue(setupNotRun());
      finishSetup.mockResolvedValue(state('On'));
      const element = await build();

      row(element, 'Giving').querySelector('[data-id="finish-setup"]').click();
      await settle();

      expect(finishSetup).toHaveBeenCalledWith({ moduleName: 'Giving' });
      expect(row(element, 'Giving').querySelector('[data-id="setup-not-run"]')).toBeNull();
      expect(row(element, 'Giving').querySelector('[data-id="finish-setup"]')).toBeNull();
    });

    it('shows the notice without the button to someone who cannot change settings', async () => {
      getState.mockResolvedValue(setupNotRun(false));
      const element = await build();

      expect(row(element, 'Giving').querySelector('[data-id="setup-not-run"]')).not.toBeNull();
      expect(row(element, 'Giving').querySelector('[data-id="finish-setup"]')).toBeNull();
    });

    it('shows the message when Finish Setup fails', async () => {
      getState.mockResolvedValue(setupNotRun());
      finishSetup.mockRejectedValue({ body: { message: 'The module could not be set up.' } });
      const element = await build();

      row(element, 'Giving').querySelector('[data-id="finish-setup"]').click();
      await settle();

      expect(element.shadowRoot.querySelector('[data-id="error"]').textContent).toContain(
        'The module could not be set up.'
      );
    });
  });
});
