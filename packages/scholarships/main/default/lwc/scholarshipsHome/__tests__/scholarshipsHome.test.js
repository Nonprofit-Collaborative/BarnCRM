import { createElement } from 'lwc';
import ScholarshipsHome from 'c/scholarshipsHome';
import getHome from '@salesforce/apex/ScholarshipsController.getHome';
import exportDisbursements from '@salesforce/apex/ScholarshipsController.exportDisbursements';
// The object info test wire adapter is emitted to on purpose, which is how a wired component is
// driven from a test.
/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { getObjectInfo } from 'lightning/uiObjectInfoApi';

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

jest.mock('@salesforce/apex/ScholarshipsController.getHome', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/ScholarshipsController.exportDisbursements',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () =>
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  new Promise((resolve) => setTimeout(resolve, 0));

function mount() {
  const element = createElement('c-scholarships-home', { is: ScholarshipsHome });
  document.body.appendChild(element);
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-scholarships-home', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists reviews, cycles and held disbursements, and exports for managers', async () => {
    getHome.mockResolvedValue({
      canManage: true,
      reviews: [{ id: 'a01000000000001AAA', name: 'APP-000001', detail: '2027' }],
      cycles: [{ id: 'a02000000000001AAA', name: '2027', detail: 'Test', count: 3 }],
      due: [{ id: 'a03000000000001AAA', name: 'DSB-000001', amount: 500, held: true }]
    });
    exportDisbursements.mockResolvedValue([{ name: 'DSB-000001', amount: 500 }]);
    const element = mount();
    await flush();
    await flush();
    expect(find(element, 'reviews').querySelectorAll('li')).toHaveLength(1);
    expect(find(element, 'cycles').querySelectorAll('li')).toHaveLength(1);
    expect(find(element, 'due').querySelector('.slds-badge')).not.toBeNull();
    find(element, 'export-button').click();
    await flush();
    expect(exportDisbursements).toHaveBeenCalled();
  });

  it('starts the export range on the local day, not the UTC day', async () => {
    jest.useFakeTimers({
      now: new Date(2026, 10, 12, 23, 30),
      doNotFake: ['setTimeout', 'clearTimeout', 'setInterval', 'clearInterval', 'setImmediate']
    });
    try {
      getHome.mockResolvedValue({ canManage: true, reviews: [], cycles: [], due: [] });
      exportDisbursements.mockResolvedValue([]);
      const element = mount();
      await flush();
      await flush();
      find(element, 'export-button').click();
      await flush();
      expect(exportDisbursements).toHaveBeenCalledWith({
        fromDate: '2026-11-01',
        toDate: '2026-11-12'
      });
    } finally {
      jest.useRealTimers();
    }
  });

  it('offers a first award program before any exists', async () => {
    getHome.mockResolvedValue({
      canManage: true,
      reviews: [],
      cycles: [],
      due: [],
      firstRun: true
    });
    const element = mount();
    await flush();
    await flush();
    const panel = find(element, 'first-run');
    expect(panel.heading).toBe('c.Scholarships_Home_FirstRunHeading');
    expect(find(element, 'first-run-new').label).toBe('c.Scholarships_Home_FirstRunNew');
  });

  it('leaves the first-run panel out once a program exists', async () => {
    getHome.mockResolvedValue({ canManage: true, reviews: [], cycles: [], due: [] });
    const element = mount();
    await flush();
    await flush();
    expect(find(element, 'first-run')).toBeNull();
  });

  it('shows New Award Program only to someone who may create one, and opens the new form', async () => {
    getHome.mockResolvedValue({ canManage: false, reviews: [], cycles: [], due: [] });
    const element = mount();
    await flush();
    expect(find(element, 'new-program')).toBeNull();

    getObjectInfo.emit({ apiName: 'Award_Program__c', createable: true });
    await flush();
    find(element, 'new-program').click();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__objectPage',
      attributes: { objectApiName: 'Award_Program__c', actionName: 'new' }
    });
  });

  it('shows the figures row, each figure a link to its list', async () => {
    getHome.mockResolvedValue({
      canManage: false,
      reviews: [{ id: 'a01000000000001AAA', name: 'APP-000001', detail: '2027' }],
      cycles: [],
      due: [],
      figures: { programs: 2, review: 7, awards: 4 }
    });
    const element = mount();
    await flush();
    await flush();
    const tiles = [...element.shadowRoot.querySelectorAll('[data-id="tiles"] c-barn-stat-tile')];
    expect(tiles.map((tile) => tile.label)).toEqual([
      'c.Scholarships_Home_FigurePrograms',
      'c.Scholarships_Home_FigureMyReviews',
      'c.Scholarships_Home_FigureInReview',
      'c.Scholarships_Home_FigureAwards'
    ]);
    expect(tiles.map((tile) => tile.value)).toEqual([2, 1, 7, 4]);
    expect(tiles[3].href).toBe('/lightning/o/Award__c/list');
  });

  it('shows no figures on the first-run panel', async () => {
    getHome.mockResolvedValue({ reviews: [], cycles: [], due: [], firstRun: true, figures: {} });
    const element = mount();
    await flush();
    await flush();
    expect(find(element, 'tiles')).toBeNull();
  });

  it('hides the export from staff and shows an error', async () => {
    getHome.mockRejectedValue({ body: { message: 'No access' } });
    const element = mount();
    await flush();
    await flush();
    expect(find(element, 'export')).toBeNull();
    expect(find(element, 'error-message').message).toBe('No access');
  });
});
