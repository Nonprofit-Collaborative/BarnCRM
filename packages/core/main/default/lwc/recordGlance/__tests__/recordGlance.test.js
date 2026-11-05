import { createElement } from 'lwc';
import RecordGlance from 'c/recordGlance';
import getCards from '@salesforce/apex/RecordGlanceController.getCards';
import { cardViews, formatDate } from '../recordGlanceModel';

jest.mock('@salesforce/apex/RecordGlanceController.getCards', () => ({ default: jest.fn() }), {
  virtual: true
});

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
    return { NavigationMixin };
  },
  { virtual: true }
);

const CARD = {
  key: 'giving',
  title: 'Giving at a Glance',
  iconName: 'custom:custom41',
  tiles: [
    { label: 'Total Giving', kind: 'currency', numberValue: 250 },
    { label: 'Last Gift Date', kind: 'date', dateValue: '2026-11-01' },
    { label: 'Donor Level', kind: 'text', textValue: 'Friend' },
    { label: 'Empty', kind: 'text', textValue: null }
  ],
  actions: [
    {
      label: 'Enter a Gift',
      pageReference: JSON.stringify({
        type: 'standard__navItemPage',
        attributes: { apiName: 'Quick_Gift_Entry' },
        state: { c__donorId: '003000000000001AAA' }
      })
    }
  ]
};

const flush = async () => {
  for (let i = 0; i < 5; i += 1) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

function mount() {
  const element = createElement('c-record-glance', { is: RecordGlance });
  element.recordId = '003000000000001AAA';
  document.body.appendChild(element);
  return element;
}

describe('c-record-glance', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('draws nothing when no module returns a card', async () => {
    getCards.mockResolvedValue([]);
    const element = mount();
    await flush();
    expect(element.shadowRoot.querySelector('lightning-card')).toBeNull();
  });

  it('draws nothing when the call fails', async () => {
    getCards.mockRejectedValue({ body: { message: 'no' } });
    const element = mount();
    await flush();
    expect(element.shadowRoot.querySelector('lightning-card')).toBeNull();
  });

  it('draws a module card with its tiles and navigates from its action', async () => {
    getCards.mockResolvedValue([CARD]);
    const element = mount();
    await flush();
    const card = element.shadowRoot.querySelector('lightning-card');
    expect(card.title).toBe('Giving at a Glance');
    const tiles = element.shadowRoot.querySelectorAll('c-barn-stat-tile');
    expect(tiles.length).toBe(3);
    expect(tiles[0].value).toBe(250);
    expect(tiles[0].formatStyle).toBe('currency');
    element.shadowRoot.querySelector('lightning-button').click();
    expect(mockNavigate).toHaveBeenCalledWith(
      expect.objectContaining({
        type: 'standard__navItemPage',
        state: { c__donorId: '003000000000001AAA' }
      })
    );
  });
});

describe('recordGlanceModel', () => {
  it('formats a date as text and leaves a bad one as given', () => {
    expect(typeof formatDate('2026-11-01', 'en-US')).toBe('string');
    expect(formatDate('2026-11-01', 'en-US')).toContain('2026');
    expect(formatDate('soon', 'en-US')).toBe('soon');
    expect(formatDate(null, 'en-US')).toBeNull();
  });

  it('keeps a zero total and drops empty values', () => {
    const [view] = cardViews(
      [
        {
          title: 'T',
          tiles: [
            { label: 'A', kind: 'currency', numberValue: 0 },
            { label: 'B', kind: 'date' }
          ]
        }
      ],
      'en-US'
    );
    expect(view.tiles.map((t) => t.label)).toEqual(['A']);
    expect(view.actions).toEqual([]);
  });
});
