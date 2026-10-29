import { createElement } from 'lwc';
import HubQuickLinks from 'c/hubQuickLinks';

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

describe('c-hub-quick-links', () => {
  afterEach(() => {
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('shows icon tiles and opens each tab by page reference, never by URL', () => {
    const element = createElement('c-hub-quick-links', { is: HubQuickLinks });
    document.body.appendChild(element);

    const tiles = Array.from(element.shadowRoot.querySelectorAll('[data-id="quick-link"]'));
    expect(tiles.map((tile) => tile.name)).toEqual([
      'Households',
      'Organizations',
      'BarnCRM_Settings'
    ]);
    expect(tiles.every((tile) => tile.iconName && tile.description && !tile.href)).toBe(true);

    tiles[1].dispatchEvent(new CustomEvent('select', { detail: { name: 'Organizations' } }));
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Organizations' }
    });
  });
});
