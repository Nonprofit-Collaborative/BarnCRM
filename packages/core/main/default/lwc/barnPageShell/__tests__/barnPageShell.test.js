import { createElement } from 'lwc';
import BarnPageShell from 'c/barnPageShell';

// Storybook-style: a standard tool page, a page under an App Page header, and the help region.
function render(props, slots = {}) {
  const element = createElement('c-barn-page-shell', { is: BarnPageShell });
  Object.assign(element, props);
  Object.entries(slots).forEach(([slot, text]) => {
    const node = document.createElement('p');
    node.textContent = text;
    if (slot !== 'default') {
      node.setAttribute('slot', slot);
    }
    element.appendChild(node);
  });
  document.body.appendChild(element);
  return element;
}

const one = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);
const flush = () => Promise.resolve();

/** Tells the shell its help slot has content, as the browser does with slotchange. */
async function fillSlot(element, name) {
  const slot = element.shadowRoot.querySelector(`slot[name="${name}"]`);
  slot.assignedNodes = () => [document.createElement('p')];
  slot.dispatchEvent(new CustomEvent('slotchange'));
  await flush();
}

describe('c-barn-page-shell', () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('story: a tool page with icon, title, purpose and actions', () => {
    const element = render(
      {
        iconName: 'standard:dashboard',
        title: 'Org Optimizer',
        purpose: 'What in your org needs attention.'
      },
      { default: 'Body', actions: 'Run Health Check' }
    );

    expect(one(element, 'icon').iconName).toBe('standard:dashboard');
    const title = one(element, 'title');
    expect(title.tagName).toBe('H1');
    expect(title.textContent).toBe('Org Optimizer');
    expect(title.className).toBe('slds-page-header__title slds-truncate');
    expect(one(element, 'purpose').textContent).toBe('What in your org needs attention.');
    expect(element.shadowRoot.querySelector('slot[name="actions"]')).not.toBeNull();
    // No help and no footer content: both stay hidden.
    expect(one(element, 'help-section').className).toContain('slds-hide');
    expect(one(element, 'footer').className).toBe('slds-hide');
  });

  it('story: under an App Page header, the title is kept for screen readers only', () => {
    const element = render({ title: 'Data Manager', titleHidden: true });
    expect(one(element, 'title').className).toBe('slds-assistive-text');
    expect(one(element, 'icon')).toBeNull();
    expect(one(element, 'purpose')).toBeNull();
  });

  it('story: help opens on the first visit and is closed on the next', async () => {
    const first = render({ title: 'Import', helpStorageKey: 'import' }, { help: 'Long help.' });
    await fillSlot(first, 'help');
    const toggle = one(first, 'help-toggle');
    expect(one(first, 'help-section').className).not.toContain('slds-hide');
    expect(one(first, 'help-section').className).toContain('slds-is-open');
    expect(toggle.getAttribute('aria-expanded')).toBe('true');
    expect(toggle.textContent).toBe('c.Core_Kit_AboutThisTool');
    document.body.removeChild(first);

    const second = render({ title: 'Import', helpStorageKey: 'import' }, { help: 'Long help.' });
    await fillSlot(second, 'help');
    expect(one(second, 'help-toggle').getAttribute('aria-expanded')).toBe('false');
    expect(one(second, 'help-section').className).not.toContain('slds-is-open');
  });

  it('remembers a person opening the help again', async () => {
    window.localStorage.setItem('barnPageShell.help.find', 'closed');
    const element = render({ title: 'Find', helpStorageKey: 'find', helpLabel: 'How Find Works' });
    await fillSlot(element, 'help');

    const toggle = one(element, 'help-toggle');
    expect(toggle.textContent).toBe('How Find Works');
    expect(toggle.getAttribute('aria-expanded')).toBe('false');
    toggle.click();
    await flush();
    expect(toggle.getAttribute('aria-expanded')).toBe('true');
    expect(window.localStorage.getItem('barnPageShell.help.find')).toBe('open');
  });

  it('still works when browser storage is blocked', async () => {
    const getItem = jest.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new Error('blocked');
    });
    const setItem = jest.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('blocked');
    });
    const element = render({ title: 'Find', helpStorageKey: 'find' });
    await fillSlot(element, 'help');
    expect(one(element, 'help-toggle').getAttribute('aria-expanded')).toBe('true');
    one(element, 'help-toggle').click();
    await flush();
    expect(one(element, 'help-toggle').getAttribute('aria-expanded')).toBe('false');
    getItem.mockRestore();
    setItem.mockRestore();
  });

  it('story: footer actions and a status message', async () => {
    const element = render(
      { title: 'Bulk Update', statusMessage: 'Preview ready.' },
      { footer: 'Back' }
    );
    await fillSlot(element, 'footer');
    expect(one(element, 'footer').className).toBe('slds-card__footer slds-text-align_left');
    const live = one(element, 'live');
    expect(live.getAttribute('role')).toBe('status');
    expect(live.getAttribute('aria-live')).toBe('polite');
    expect(live.textContent).toBe('Preview ready.');
  });
});
