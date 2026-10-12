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
});
