import { createElement } from 'lwc';
import BarnSaveBar from 'c/barnSaveBar';

jest.mock('@salesforce/label/c.Core_Kit_UnsavedMany', () => ({ default: '{0} unsaved changes' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_Kit_UnsavedOne', () => ({ default: '1 unsaved change' }), {
  virtual: true
});

// Storybook-style: nothing unsaved, one change, several changes while saving.
function render(props) {
  const element = createElement('c-barn-save-bar', { is: BarnSaveBar });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

const one = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

function unload() {
  const event = new CustomEvent('beforeunload', { cancelable: true });
  window.dispatchEvent(event);
  return event.defaultPrevented;
}

describe('c-barn-save-bar', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('story: nothing unsaved shows no buttons but keeps the live region', () => {
    const element = render({ dirtyCount: 0 });
    expect(one(element, 'bar').className).toBe('slds-assistive-text');
    expect(one(element, 'count').getAttribute('aria-live')).toBe('polite');
    expect(one(element, 'count').textContent).toBe('');
    expect(one(element, 'save')).toBeNull();
    expect(unload()).toBe(false);
  });

  it('story: one change docks the bar and fires save and discard', () => {
    const element = render({ dirtyCount: 1 });
    const saved = jest.fn();
    const discarded = jest.fn();
    element.addEventListener('save', saved);
    element.addEventListener('discard', discarded);

    expect(one(element, 'bar').className).toBe('savebar');
    expect(one(element, 'count').textContent).toBe('1 unsaved change');
    expect(one(element, 'save').variant).toBe('brand');
    one(element, 'save').click();
    one(element, 'discard').click();
    expect(saved).toHaveBeenCalledTimes(1);
    expect(discarded).toHaveBeenCalledTimes(1);
    expect(unload()).toBe(true);
  });

  it('story: several changes while saving disable both buttons', () => {
    const element = render({ dirtyCount: 4, saving: true });
    expect(one(element, 'count').textContent).toBe('4 unsaved changes');
    expect(one(element, 'save').disabled).toBe(true);
    expect(one(element, 'discard').disabled).toBe(true);
  });

  it('stops asking on leave once removed', () => {
    const element = render({ dirtyCount: 2 });
    document.body.removeChild(element);
    expect(unload()).toBe(false);
  });
});
