import { createElement } from 'lwc';

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
import VolunteersHome from 'c/volunteersHome';
import getHome from '@salesforce/apex/VolunteersHomeController.getHome';
import { setHelpTextForTest, clearHelpTextForTest } from 'c/barnHelpText';
import { badgeStatusFor, pageReferenceFor, valueFor } from '../volunteersHomeModel';

jest.mock('@salesforce/apex/VolunteersHomeController.getHome', () => ({ default: jest.fn() }), {
  virtual: true
});

const TILES = [
  {
    name: 'hoursThisMonth',
    label: 'Hours This Month',
    value: 42.5,
    badgeLabel: 'Approved',
    badgeStatus: 'done',
    objectApiName: 'Volunteer_Hours__c',
    filterName: 'All_Volunteer_Hours'
  },
  {
    name: 'hoursToApprove',
    label: 'Volunteer Hours',
    value: 0,
    badgeLabel: 'Submitted',
    badgeStatus: 'due',
    objectApiName: 'Volunteer_Hours__c',
    tabName: 'Volunteer_Approve_Hours'
  }
];

async function flush() {
  for (let i = 0; i < 5; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
}

function build() {
  const element = createElement('c-volunteers-home', { is: VolunteersHome });
  document.body.appendChild(element);
  return element;
}

describe('c-volunteers-home', () => {
  beforeEach(() => {
    setHelpTextForTest({ Volunteers_Home_LoadError: 'The figures were not loaded.' });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    clearHelpTextForTest();
    jest.clearAllMocks();
  });

  it('shows each figure and opens its list or tab', async () => {
    getHome.mockResolvedValue(TILES);
    const element = build();
    await flush();

    const tiles = element.shadowRoot.querySelectorAll('c-barn-stat-tile');
    expect(tiles).toHaveLength(2);
    expect(tiles[0].value).toBe(42.5);
    expect(tiles[0].badgeVariant).toBe('done');
    expect(tiles[1].badgeVariant).toBe('neutral');

    tiles[1].dispatchEvent(new CustomEvent('select', { detail: { name: 'hoursToApprove' } }));
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Volunteer_Approve_Hours' }
    });
  });

  it('says so when the figures do not load', async () => {
    getHome.mockRejectedValue({ body: { message: 'no' } });
    const element = build();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="error"]').message).toBe(
      'The figures were not loaded.'
    );
  });

  it('opens a list view and shows a capped count with a plus', () => {
    expect(pageReferenceFor(TILES[0])).toEqual({
      type: 'standard__objectPage',
      attributes: { objectApiName: 'Volunteer_Hours__c', actionName: 'list' },
      state: { filterName: 'All_Volunteer_Hours' }
    });
    expect(valueFor({ value: 2000, capped: true }, 'en-US')).toBe('2,000+');
    expect(valueFor({ value: 104.37, currencyCode: 'USD' }, 'en-US')).toBe('$104.37');
    expect(badgeStatusFor({ value: 3 })).toBeUndefined();
  });
});
