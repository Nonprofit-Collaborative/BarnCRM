import { createElement } from 'lwc';
import ScholarshipsHome from 'c/scholarshipsHome';
import getHome from '@salesforce/apex/ScholarshipsController.getHome';
import exportDisbursements from '@salesforce/apex/ScholarshipsController.exportDisbursements';

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

  it('hides the export from staff and shows an error', async () => {
    getHome.mockRejectedValue({ body: { message: 'No access' } });
    const element = mount();
    await flush();
    await flush();
    expect(find(element, 'export')).toBeNull();
    expect(find(element, 'error-message').message).toBe('No access');
  });
});
