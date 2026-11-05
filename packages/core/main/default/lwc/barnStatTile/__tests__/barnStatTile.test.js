import { createElement } from 'lwc';
import BarnStatTile from 'c/barnStatTile';

// Storybook-style: a number, text in place of a number, the formats, the badge, and the
// link, button and row-tile options.
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

  it('story: a number is formatted, with its label, centered and no badge (the default)', () => {
    const element = render({ label: 'Would Add', value: 1250 });
    const formatted = one(element, 'value').querySelector('lightning-formatted-number');
    expect(formatted.value).toBe(1250);
    expect(formatted.formatStyle).toBe('decimal');
    expect(one(element, 'label').textContent).toBe('Would Add');
    expect(one(element, 'badge')).toBeNull();
    expect(one(element, 'icon')).toBeNull();
    expect(one(element, 'tile').tagName).toBe('DIV');
    expect(one(element, 'tile').className).toBe('stat');
  });

  it('story: text is shown as given', () => {
    const element = render({ label: 'People', value: 'More than 2,000' });
    expect(one(element, 'value').querySelector('lightning-formatted-number')).toBeNull();
    expect(one(element, 'value').textContent).toBe('More than 2,000');
  });

  it.each([
    ['currency', 'currency'],
    ['percent', 'percent'],
    ['number', 'decimal'],
    ['unknown', 'decimal']
  ])('story: format-style %s', (formatStyle, expected) => {
    const element = render({ label: 'Open Asks', value: 4500, formatStyle, currencyCode: 'USD' });
    const formatted = one(element, 'value').querySelector('lightning-formatted-number');
    expect(formatted.formatStyle).toBe(expected);
    expect(formatted.currencyCode).toBe('USD');
  });

  it.each([
    ['success', 'success'],
    ['overdue', 'overdue'],
    [undefined, undefined]
  ])('story: badge status %s goes to the status badge', (variant, expected) => {
    const element = render({
      label: 'Rejected',
      value: 3,
      badgeLabel: 'Check',
      badgeVariant: variant
    });
    const badge = one(element, 'badge');
    expect(badge.label).toBe('Check');
    expect(badge.status).toBe(expected);
  });

  it('story: a bordered row tile with an icon, as a link', () => {
    const element = render({
      label: 'Open Asks',
      value: 7,
      iconName: 'custom:custom54',
      align: 'start',
      bordered: true,
      href: '/lightning/n/Ask_Pipeline'
    });
    const tile = one(element, 'tile');
    expect(tile.tagName).toBe('A');
    expect(tile.getAttribute('href')).toBe('/lightning/n/Ask_Pipeline');
    expect(tile.className).toBe('stat stat_start stat_bordered stat_action');
    expect(one(element, 'icon').iconName).toBe('custom:custom54');
  });

  it('story: a clickable tile fires select with its name', () => {
    const element = render({ label: 'Errors', value: 2, clickable: true, name: 'errors' });
    const handler = jest.fn();
    element.addEventListener('select', handler);
    const tile = one(element, 'tile');
    expect(tile.tagName).toBe('BUTTON');
    tile.click();
    expect(handler.mock.calls[0][0].detail).toEqual({ name: 'errors' });
  });
});
