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

  it('opens each tab by page reference, never by URL', () => {
    const element = createElement('c-hub-quick-links', { is: HubQuickLinks });
    document.body.appendChild(element);

    const buttons = element.shadowRoot.querySelectorAll('lightning-button');
    expect(Array.from(buttons).map((button) => button.dataset.tab)).toEqual([
      'Households',
      'Organizations',
      'BarnCRM_Settings'
    ]);
    expect(element.shadowRoot.querySelector('a[href]')).toBeNull();

    buttons[1].click();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Organizations' }
    });
  });
});
