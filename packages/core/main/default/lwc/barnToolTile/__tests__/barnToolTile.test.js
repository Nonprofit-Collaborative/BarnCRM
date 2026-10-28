import { createElement } from 'lwc';
import BarnToolTile from 'c/barnToolTile';

// Storybook-style: button tile, link tile, badge variants and a disabled tile.
function render(props) {
  const element = createElement('c-barn-tool-tile', { is: BarnToolTile });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

const one = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

const IMPORT = {
  name: 'import',
  label: 'Import',
  description: 'Add or update records from a spreadsheet.',
  iconName: 'standard:data_streams'
};

describe('c-barn-tool-tile', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('story: a button tile fires select with its name', () => {
    const element = render(IMPORT);
    const handler = jest.fn();
    element.addEventListener('select', handler);

    const tile = one(element, 'tile');
    expect(tile.tagName).toBe('BUTTON');
    expect(tile.getAttribute('type')).toBe('button');
    expect(tile.getAttribute('aria-disabled')).toBe('false');
    expect(one(element, 'name').textContent).toBe('Import');
    expect(one(element, 'line').textContent).toBe('Add or update records from a spreadsheet.');
    expect(one(element, 'icon').iconName).toBe('standard:data_streams');
    expect(one(element, 'badge')).toBeNull();

    tile.click();
    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail).toEqual({ name: 'import' });
  });

  it('story: a link tile', () => {
    const element = render({ ...IMPORT, href: '/lightning/n/Import' });
    const tile = one(element, 'tile');
    expect(tile.tagName).toBe('A');
    expect(tile.getAttribute('href')).toBe('/lightning/n/Import');
  });

  it.each([
    ['success', 'slds-theme_success'],
    ['warning', 'slds-theme_warning'],
    ['error', 'slds-theme_error'],
    ['inverse', 'slds-badge_inverse'],
    [undefined, '']
  ])('story: badge variant %s', async (variant, expected) => {
    const element = render({ ...IMPORT, badgeLabel: '3 Need Attention', badgeVariant: variant });
    await Promise.resolve();
    const badge = one(element, 'badge');
    expect(badge.label).toBe('3 Need Attention');
    expect(badge.className).toBe(expected);
  });

  it('story: disabled shows its reason, stays focusable and fires nothing', () => {
    const element = render({
      ...IMPORT,
      href: '/lightning/n/Import',
      disabled: true,
      disabledReason: 'Needs the Import permission set.'
    });
    const handler = jest.fn();
    element.addEventListener('select', handler);

    const tile = one(element, 'tile');
    expect(tile.tagName).toBe('BUTTON');
    expect(tile.getAttribute('aria-disabled')).toBe('true');
    expect(tile.hasAttribute('disabled')).toBe(false);
    expect(tile.className).toContain('tile_disabled');
    expect(one(element, 'line').textContent).toBe('Needs the Import permission set.');

    tile.click();
    expect(handler).not.toHaveBeenCalled();
  });
});
