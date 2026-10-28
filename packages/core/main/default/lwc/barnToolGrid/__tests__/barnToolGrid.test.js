import { createElement } from 'lwc';
import BarnToolGrid from 'c/barnToolGrid';

// Storybook-style: a Data Manager-like hub with grouped tiles.
const GROUPS = [
  {
    name: 'in',
    label: 'Bring Data In',
    tiles: [
      {
        name: 'import',
        label: 'Import',
        description: 'From a spreadsheet.',
        iconName: 'standard:data_streams'
      }
    ]
  },
  {
    name: 'change',
    label: 'Find and Change',
    tiles: [
      {
        name: 'find',
        label: 'Find',
        description: 'Find and export records.',
        iconName: 'standard:search'
      },
      {
        name: 'update',
        label: 'Bulk Update',
        description: 'Change many records.',
        iconName: 'standard:record_update'
      }
    ]
  },
  { name: 'empty', label: 'Nothing Here', tiles: [] },
  {
    name: 'careful',
    label: 'Careful',
    tiles: [
      {
        name: 'delete',
        label: 'Bulk Delete',
        description: 'Delete many records.',
        iconName: 'standard:record_delete',
        badgeLabel: 'Undo for 15 Days',
        badgeVariant: 'warning'
      }
    ]
  }
];

function render(props) {
  const element = createElement('c-barn-tool-grid', { is: BarnToolGrid });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

const all = (element, id) => Array.from(element.shadowRoot.querySelectorAll(`[data-id="${id}"]`));

describe('c-barn-tool-grid', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('story: groups with headings, empty groups left out', () => {
    const element = render({ groups: GROUPS });

    const headings = all(element, 'group-heading');
    expect(headings.map((node) => node.textContent.trim())).toEqual([
      'Bring Data In',
      'Find and Change',
      'Careful'
    ]);
    expect(headings[0].getAttribute('role')).toBe('heading');
    expect(headings[0].getAttribute('aria-level')).toBe('2');

    const tiles = Array.from(element.shadowRoot.querySelectorAll('c-barn-tool-tile'));
    expect(tiles.map((tile) => tile.name)).toEqual(['import', 'find', 'update', 'delete']);
    expect(tiles[3].badgeLabel).toBe('Undo for 15 Days');
    expect(tiles[3].badgeVariant).toBe('warning');
    expect(tiles[0].disabled).toBe(false);

    const cell = tiles[0].parentElement;
    expect(cell.tagName).toBe('LI');
    expect(cell.className).toContain('slds-size_1-of-1');
    expect(cell.className).toContain('slds-large-size_1-of-3');
  });

  it('story: inside a card, headings at level 3', () => {
    const element = render({ groups: GROUPS, headingLevel: 3 });
    expect(all(element, 'group-heading')[0].getAttribute('aria-level')).toBe('3');
  });

  it('passes a tile select up with the tile name', () => {
    const element = render({ groups: GROUPS });
    const handler = jest.fn();
    element.addEventListener('select', handler);

    const tile = element.shadowRoot.querySelectorAll('c-barn-tool-tile')[1];
    tile.dispatchEvent(new CustomEvent('select', { detail: { name: 'find' } }));

    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail).toEqual({ name: 'find' });
  });

  it('renders nothing for no groups', () => {
    const element = render({ groups: null });
    expect(all(element, 'group')).toHaveLength(0);
  });
});
