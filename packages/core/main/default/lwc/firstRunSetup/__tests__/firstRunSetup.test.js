import { createElement } from 'lwc';
import FirstRunSetup from 'c/firstRunSetup';
import getState from '@salesforce/apex/FirstRunController.getState';
import finish from '@salesforce/apex/FirstRunController.finish';

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

const FEATURES = [
  { key: 'DataManager', name: 'Data Manager', description: 'Bulk tools.', isOn: false },
  { key: 'Relationships', name: 'Relationships', description: 'Both sides.', isOn: false },
  { key: 'Addresses', name: 'Addresses', description: 'Seasonal.', isOn: false }
];

const ADMIN_STATE = {
  needsSetup: true,
  canFinish: true,
  recommendedSuite: 'Community',
  features: FEATURES
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

function byId(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

function all(element, id) {
  return Array.from(element.shadowRoot.querySelectorAll(`[data-id="${id}"]`));
}

function choose(element, id, value) {
  byId(element, id).dispatchEvent(new CustomEvent('change', { detail: { value } }));
}

describe('c-first-run-setup', () => {
  beforeEach(() => {
    finish.mockResolvedValue({ needsSetup: false, canFinish: true, features: [] });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows nothing once setup is finished', async () => {
    getState.mockResolvedValue({ needsSetup: false, canFinish: true, features: [] });
    const element = await build();

    expect(byId(element, 'first-run')).toBeNull();
  });

  it('blocks nothing when the state cannot be read, and says so', async () => {
    getState.mockRejectedValue({ body: { message: 'nope' } });
    const element = await build();

    expect(byId(element, 'first-run')).toBeNull();
    expect(byId(element, 'load-error').textContent).toBe('nope');
  });

  describe('keyboard', () => {
    let focus;
    let originalFocus;

    beforeEach(() => {
      originalFocus = HTMLElement.prototype.focus;
      focus = jest.fn();
      HTMLElement.prototype.focus = focus;
    });

    afterEach(() => {
      HTMLElement.prototype.focus = originalFocus;
    });

    function tab(target, shiftKey = false) {
      const event = new KeyboardEvent('keydown', {
        key: 'Tab',
        shiftKey,
        bubbles: true,
        composed: true,
        cancelable: true
      });
      target.dispatchEvent(event);
      return event;
    }

    it('starts on the first control', async () => {
      getState.mockResolvedValue(ADMIN_STATE);
      const element = await build();

      expect(focus.mock.instances[0]).toBe(byId(element, 'edition'));
    });

    it('wraps Tab from the last control to the first, and Shift+Tab back', async () => {
      getState.mockResolvedValue(ADMIN_STATE);
      const element = await build();
      focus.mockClear();

      const forward = tab(byId(element, 'finish'));
      expect(forward.defaultPrevented).toBe(true);
      expect(focus.mock.instances[0]).toBe(byId(element, 'edition'));

      const back = tab(byId(element, 'edition'), true);
      expect(back.defaultPrevented).toBe(true);
      expect(focus.mock.instances[1]).toBe(byId(element, 'finish'));
    });

    it('leaves Tab alone between controls', async () => {
      getState.mockResolvedValue(ADMIN_STATE);
      const element = await build();

      expect(tab(byId(element, 'edition')).defaultPrevented).toBe(false);
    });

    it('keeps focus on the window when it has no control', async () => {
      getState.mockResolvedValue({ needsSetup: true, canFinish: false, features: [] });
      const element = await build();
      focus.mockClear();

      const event = tab(byId(element, 'admin-needed'));
      expect(event.defaultPrevented).toBe(true);
      expect(focus.mock.instances[0]).toBe(byId(element, 'first-run'));
    });
  });

  it('tells someone who cannot finish that an administrator needs to', async () => {
    getState.mockResolvedValue({ needsSetup: true, canFinish: false, features: [] });
    const element = await build();

    expect(byId(element, 'first-run')).not.toBeNull();
    expect(byId(element, 'admin-needed').textContent).toBe('c.Core_FirstRun_AdminNeeded');
    expect(byId(element, 'finish')).toBeNull();
    expect(byId(element, 'edition')).toBeNull();
  });

  it('turns on every feature by default and lands on General', async () => {
    getState.mockResolvedValue(ADMIN_STATE);
    const element = await build();
    const finished = jest.fn();
    element.addEventListener('setupfinished', finished);

    expect(byId(element, 'edition').value).toBe('Community');
    expect(all(element, 'feature')).toHaveLength(0);
    byId(element, 'finish').click();
    await settle();

    expect(finish).toHaveBeenCalledWith({
      suite: 'Community',
      featureKeys: ['DataManager', 'Relationships', 'Addresses']
    });
    expect(finished).toHaveBeenCalledTimes(1);
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'BarnCRM_Settings' },
      state: { c__section: 'General' }
    });
    expect(byId(element, 'first-run')).toBeNull();
  });

  it('lists every feature ticked when choosing, and leaves an unticked one off', async () => {
    getState.mockResolvedValue(ADMIN_STATE);
    const element = await build();

    choose(element, 'edition', 'Impact');
    choose(element, 'mode', 'choose');
    await settle();
    const boxes = all(element, 'feature');
    expect(boxes.map((box) => box.checked)).toEqual([true, true, true]);

    boxes[1].checked = false;
    boxes[1].dispatchEvent(new CustomEvent('change'));
    await settle();
    byId(element, 'finish').click();
    await settle();

    expect(finish).toHaveBeenCalledWith({
      suite: 'Impact',
      featureKeys: ['DataManager', 'Addresses']
    });
  });

  it('keeps the window and shows the message when finishing fails', async () => {
    getState.mockResolvedValue(ADMIN_STATE);
    finish.mockRejectedValue({ body: { message: 'Setup could not be finished.' } });
    const element = await build();

    byId(element, 'finish').click();
    await settle();

    expect(byId(element, 'first-run')).not.toBeNull();
    expect(byId(element, 'error').textContent.trim()).toBe('Setup could not be finished.');
  });
});
