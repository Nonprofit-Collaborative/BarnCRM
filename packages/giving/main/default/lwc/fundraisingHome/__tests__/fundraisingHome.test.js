import { createElement } from 'lwc';
import FundraisingHome from 'c/fundraisingHome';
import getHome from '@salesforce/apex/FundraisingHomeController.getHome';

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

const getNavigateCalledWith = () => ({
  pageReference: mockNavigate.mock.calls[mockNavigate.mock.calls.length - 1][0]
});
jest.mock('@salesforce/apex/FundraisingHomeController.getHome', () => ({ default: jest.fn() }), {
  virtual: true
});

const HOME = {
  canEnterGift: true,
  tiles: [
    {
      name: 'giftsToThank',
      label: 'Gifts',
      count: 4,
      badgeLabel: 'To acknowledge',
      badgeStatus: 'due',
      objectApiName: 'Gift__c',
      tabName: 'Acknowledgments'
    },
    {
      name: 'installmentsOverdue',
      label: 'Installments',
      count: 0,
      badgeLabel: 'Overdue',
      badgeStatus: 'overdue',
      objectApiName: 'Installment__c',
      filterName: 'Overdue'
    },
    {
      name: 'myAsksDue',
      label: 'My Asks Due This Month',
      count: 2001,
      capped: true,
      objectApiName: 'Ask__c',
      filterName: 'My_Asks_Due_This_Month'
    }
  ],
  setupTiles: [
    { name: 'Donor_Levels', label: 'Donor Level Ladder' },
    { name: 'Receipts', label: 'Receipt Letters' }
  ]
};

const flush = async () => {
  for (let i = 0; i < 5; i += 1) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

async function render(home = HOME) {
  getHome.mockResolvedValue(home);
  const element = createElement('c-fundraising-home', { is: FundraisingHome });
  document.body.appendChild(element);
  await flush();
  return element;
}

describe('c-fundraising-home', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows each figure as a stat tile, with a quiet badge when the count is zero', async () => {
    const element = await render();
    const thank = element.shadowRoot.querySelector('[data-id="giftsToThank"]');
    expect(thank.label).toBe('Gifts');
    expect(thank.value).toBe(4);
    expect(thank.badgeVariant).toBe('due');
    expect(thank.iconName).toBe('custom:custom71');
    const overdue = element.shadowRoot.querySelector('[data-id="installmentsOverdue"]');
    expect(overdue.badgeVariant).toBe('neutral');
    const asks = element.shadowRoot.querySelector('[data-id="myAsksDue"]');
    expect(String(asks.value).endsWith('+')).toBe(true);
  });

  it('opens the list or page behind a figure', async () => {
    const element = await render();
    element.shadowRoot
      .querySelector('[data-id="installmentsOverdue"]')
      .dispatchEvent(new CustomEvent('select', { detail: { name: 'installmentsOverdue' } }));
    expect(getNavigateCalledWith().pageReference).toEqual({
      type: 'standard__objectPage',
      attributes: { objectApiName: 'Installment__c', actionName: 'list' },
      state: { filterName: 'Overdue' }
    });
  });

  it('opens Quick Gift Entry from Enter a Gift', async () => {
    const element = await render();
    const button = element.shadowRoot.querySelector('[data-id="enter-gift"]');
    expect(button.label).toBe('c.Giving_FundraisingHome_EnterGift');
    button.click();
    expect(getNavigateCalledWith().pageReference).toEqual({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Quick_Gift_Entry' }
    });
  });

  it('lists the setup pages under Fundraising Setup with their tab icons', async () => {
    const element = await render();
    const grid = element.shadowRoot.querySelector('[data-id="setup"]');
    const [group] = grid.groups;
    expect(group.label).toBe('c.Giving_FundraisingHome_SetupGroup');
    expect(group.tiles.map((tile) => tile.name)).toEqual(['Donor_Levels', 'Receipts']);
    expect(group.tiles[0].iconName).toBe('custom:custom65');
    expect(group.tiles[0].description).toBe('c.Giving_FundraisingHome_DonorLevelsHelp');
    grid.dispatchEvent(new CustomEvent('select', { detail: { name: 'Receipts' } }));
    expect(getNavigateCalledWith().pageReference).toEqual({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Receipts' }
    });
  });

  it('hides Enter a Gift and the setup group from someone who may use neither', async () => {
    const element = await render({ canEnterGift: false, tiles: [], setupTiles: [] });
    expect(element.shadowRoot.querySelector('[data-id="enter-gift"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="setup"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="tiles"]')).toBeNull();
  });

  it('says so in an error notice when the page cannot load', async () => {
    getHome.mockRejectedValue(new Error('boom'));
    const element = createElement('c-fundraising-home', { is: FundraisingHome });
    document.body.appendChild(element);
    await flush();
    const notice = element.shadowRoot.querySelector('[data-id="error"]');
    expect(notice.variant).toBe('error');
    expect(notice.message).toBe('c.Giving_FundraisingHome_LoadError');
  });
});
