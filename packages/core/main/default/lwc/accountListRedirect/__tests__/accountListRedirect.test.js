import { createElement } from 'lwc';
import AccountListRedirect from 'c/accountListRedirect';

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
    return { NavigationMixin, __esModule: true };
  },
  { virtual: true }
);

function render() {
  const element = createElement('c-account-list-redirect', { is: AccountListRedirect });
  element.filterName = 'Households';
  element.linkLabel = 'Open Households';
  document.body.appendChild(element);
  return element;
}

describe('c-account-list-redirect', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    mockNavigate.mockClear();
  });

  it('replaces itself with the named Account list view', () => {
    render();
    expect(mockNavigate).toHaveBeenCalledTimes(1);
    expect(mockNavigate).toHaveBeenCalledWith(
      {
        type: 'standard__objectPage',
        attributes: { objectApiName: 'Account', actionName: 'list' },
        state: { filterName: 'Households' }
      },
      true
    );
  });

  it('shows a fallback link that navigates without replacing', () => {
    const element = render();
    const link = element.shadowRoot.querySelector('[data-id="open"]');
    expect(link.textContent).toBe('Open Households');
    link.click();
    expect(mockNavigate).toHaveBeenCalledTimes(2);
    expect(mockNavigate.mock.calls[1][1]).toBe(false);
  });
});
