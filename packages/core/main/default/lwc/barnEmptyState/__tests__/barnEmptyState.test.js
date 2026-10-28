import { createElement } from 'lwc';
import BarnEmptyState from 'c/barnEmptyState';

// Storybook-style: one case per illustration and size a screen can ask for.
function render(props, actionLabel) {
  const element = createElement('c-barn-empty-state', { is: BarnEmptyState });
  Object.assign(element, props);
  if (actionLabel) {
    const button = document.createElement('button');
    button.textContent = actionLabel;
    element.appendChild(button);
  }
  document.body.appendChild(element);
  return element;
}

const one = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-barn-empty-state', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('story: no data, small, with an action', () => {
    const element = render(
      { heading: 'No Data Jobs Yet', message: 'Each import is listed here.' },
      'Import a File'
    );

    expect(one(element, 'art-no-data')).not.toBeNull();
    expect(one(element, 'art-no-data').getAttribute('aria-hidden')).toBe('true');
    expect(one(element, 'empty-state').className).toBe('slds-illustration slds-illustration_small');
    const heading = one(element, 'heading');
    expect(heading.textContent.trim()).toBe('No Data Jobs Yet');
    expect(heading.getAttribute('role')).toBe('heading');
    expect(heading.getAttribute('aria-level')).toBe('3');
    expect(one(element, 'message').textContent).toBe('Each import is listed here.');
    // The action is the caller's own control, placed in the default slot under the text.
    expect(one(element, 'action').querySelector('slot')).not.toBeNull();
  });

  it('story: all clear, large page, heading level 2', () => {
    const element = render({
      illustration: 'all-clear',
      heading: 'All Clear',
      size: 'large',
      headingLevel: 2
    });

    expect(one(element, 'art-all-clear')).not.toBeNull();
    expect(one(element, 'art-no-data')).toBeNull();
    expect(one(element, 'empty-state').className).toBe('slds-illustration slds-illustration_large');
    expect(one(element, 'heading').getAttribute('aria-level')).toBe('2');
    expect(one(element, 'message')).toBeNull();
  });

  it('story: setup', () => {
    const element = render({ illustration: 'setup', heading: 'Run Health Check First' });
    expect(one(element, 'art-setup')).not.toBeNull();
  });

  it('draws no data for an unknown illustration name', () => {
    const element = render({ illustration: 'open-road', heading: 'Nothing Yet' });
    expect(one(element, 'art-no-data')).not.toBeNull();
  });
});
