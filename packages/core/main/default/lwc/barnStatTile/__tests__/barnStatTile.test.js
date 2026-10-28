import { createElement } from 'lwc';
import BarnStatTile from 'c/barnStatTile';

// Storybook-style: a number, text in place of a number, and the badge variants.
function render(props) {
  const element = createElement('c-barn-stat-tile', { is: BarnStatTile });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

const one = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-barn-stat-tile', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('story: a number is formatted, with its label and no badge', () => {
    const element = render({ label: 'Would Add', value: 1250 });
    const formatted = one(element, 'value').querySelector('lightning-formatted-number');
    expect(formatted.value).toBe(1250);
    expect(one(element, 'label').textContent).toBe('Would Add');
    expect(one(element, 'badge')).toBeNull();
  });

  it('story: text is shown as given', () => {
    const element = render({ label: 'People', value: 'More than 2,000' });
    expect(one(element, 'value').querySelector('lightning-formatted-number')).toBeNull();
    expect(one(element, 'value').textContent).toBe('More than 2,000');
  });

  it.each([
    ['success', 'slds-theme_success'],
    ['warning', 'slds-theme_warning'],
    ['error', 'slds-theme_error'],
    ['inverse', 'slds-badge_inverse'],
    [undefined, '']
  ])('story: badge variant %s', (variant, expected) => {
    const element = render({
      label: 'Rejected',
      value: 3,
      badgeLabel: 'Check',
      badgeVariant: variant
    });
    const badge = one(element, 'badge');
    expect(badge.label).toBe('Check');
    expect(badge.className).toBe(expected);
  });
});
