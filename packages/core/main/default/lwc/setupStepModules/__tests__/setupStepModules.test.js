import { createElement } from 'lwc';
import SetupStepModules from 'c/setupStepModules';

const MODULES = [
  { name: 'Core', present: true, docsUrl: 'https://example.invalid/core' },
  { name: 'Giving', present: false, docsUrl: 'https://example.invalid/giving' }
];

const PUBLISHED = '/packaging/installPackage.apexp?p0=04t000000000001AAA';

function build() {
  const element = createElement('c-setup-step-modules', { is: SetupStepModules });
  element.modules = MODULES;
  document.body.appendChild(element);
  return element;
}

describe('c-setup-step-modules', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('says which modules are here and which are not', () => {
    const element = build();

    const items = element.shadowRoot.querySelectorAll('li');
    expect(items).toHaveLength(2);
    expect(items[0].textContent).toContain('Core_SetupAssistant_ModulePresent');
    expect(items[1].textContent).toContain('Core_SetupAssistant_ModuleAbsent');
  });

  it('links each module to what it does', () => {
    const element = build();

    const links = element.shadowRoot.querySelectorAll('a');
    expect(links).toHaveLength(2);
    expect(links[1].href).toContain('giving');
  });

  it('says plainly that one click module control comes later', () => {
    const element = build();

    expect(element.shadowRoot.textContent).toContain('Core_SetupAssistant_ModuleManagerNotice');
  });

  it('links a published module that is not here to its installer in a new tab', () => {
    const element = createElement('c-setup-step-modules', { is: SetupStepModules });
    element.modules = [MODULES[0], { ...MODULES[1], installUrl: PUBLISHED }];
    document.body.appendChild(element);

    const install = element.shadowRoot.querySelectorAll('[data-id="install-link"]');
    expect(install).toHaveLength(1);
    expect(install[0].getAttribute('href')).toBe(PUBLISHED);
    expect(install[0].target).toBe('_blank');
  });

  it('offers no installer for a module with no published version', () => {
    const element = build();

    expect(element.shadowRoot.querySelectorAll('[data-id="install-link"]')).toHaveLength(0);
  });

  it('names a module by its BarnCRM label when it has one', () => {
    const element = createElement('c-setup-step-modules', { is: SetupStepModules });
    element.modules = [MODULES[0], { ...MODULES[1], label: 'BarnCRM Giving' }];
    document.body.appendChild(element);

    const names = element.shadowRoot.querySelectorAll('[data-id="module-name"]');
    expect(Array.from(names).map((name) => name.textContent)).toEqual(['Core', 'BarnCRM Giving']);
  });

  it('says which modules to install first for one that is not here', () => {
    const element = createElement('c-setup-step-modules', { is: SetupStepModules });
    element.modules = [
      { ...MODULES[0], installFirst: 'Ignored once here' },
      { ...MODULES[1], installFirst: 'BarnCRM Rollup Builder' }
    ];
    document.body.appendChild(element);

    expect(element.shadowRoot.querySelectorAll('[data-id="install-first"]')).toHaveLength(1);
  });

  it('lists an installed module pages to add to the BarnCRM apps, with how', () => {
    const element = createElement('c-setup-step-modules', { is: SetupStepModules });
    element.modules = [
      MODULES[0],
      {
        name: 'Giving',
        present: true,
        staffTabs: 'Gifts, Commitments',
        adminTabs: 'Accounting Periods'
      },
      { name: 'Volunteers', present: false, staffTabs: 'Ignored until here' }
    ];
    document.body.appendChild(element);

    const staff = element.shadowRoot.querySelectorAll('[data-id="staff-tabs"]');
    expect(staff).toHaveLength(1);
    expect(staff[0].textContent).toContain('Core_SetupAssistant_ModuleStaffTabs');
    expect(element.shadowRoot.querySelectorAll('[data-id="admin-tabs"]')).toHaveLength(1);
    expect(element.shadowRoot.querySelector('[data-id="tabs-how"]')).not.toBeNull();
  });

  it('says nothing about tabs when no installed module has any', () => {
    const element = build();

    expect(element.shadowRoot.querySelector('[data-id="tabs-how"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="staff-tabs"]')).toBeNull();
  });
});
