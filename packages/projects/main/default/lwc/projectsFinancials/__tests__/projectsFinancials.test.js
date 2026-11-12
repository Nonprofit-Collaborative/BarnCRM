import { createElement } from 'lwc';
import ProjectsFinancials from 'c/projectsFinancials';
import getFinancials from '@salesforce/apex/ProjectBillingController.getFinancials';
import recognizeRevenue from '@salesforce/apex/ProjectBillingController.recognizeRevenue';

jest.mock(
  '@salesforce/apex/ProjectBillingController.getFinancials',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/apex/ProjectBillingController.recognizeRevenue',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const PROJECT = 'a01000000000001AAA';
const flush = () =>
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  new Promise((resolve) => setTimeout(resolve, 0));

function mount() {
  const element = createElement('c-projects-financials', { is: ProjectsFinancials });
  element.recordId = PROJECT;
  document.body.appendChild(element);
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);
const CARD = {
  enabled: true,
  canManage: true,
  withCost: true,
  budget: 6000,
  revenue: 3000,
  cost: 1200,
  invoiced: 1000,
  months: [{ month: '2026-10-01', recognized: 2000, cost: 1000 }]
};

describe('c-projects-financials', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows the figures, the months with the open one, and recognizes a month', async () => {
    getFinancials.mockResolvedValue(CARD);
    recognizeRevenue.mockResolvedValue('a03000000000001AAA');
    const element = mount();
    await flush();
    expect(find(element, 'unbilled').value).toBe(2000);
    expect(find(element, 'margin')).not.toBeNull();
    expect(element.shadowRoot.querySelectorAll('[data-id="month-row"]')).toHaveLength(2);
    const month = find(element, 'month');
    month.value = '2026-09-01';
    month.dispatchEvent(new CustomEvent('change'));
    find(element, 'recognize').click();
    await flush();
    expect(recognizeRevenue).toHaveBeenCalledWith({ projectId: PROJECT, month: '2026-09-01' });
    expect(find(element, 'notice')).not.toBeNull();
  });

  it('hides cost, margin and Recognize Revenue from staff, and everything while off', async () => {
    getFinancials.mockResolvedValueOnce({ ...CARD, withCost: false, cost: null, canManage: false });
    const element = mount();
    await flush();
    expect(find(element, 'cost')).toBeNull();
    expect(find(element, 'margin')).toBeNull();
    expect(find(element, 'recognize')).toBeNull();
    getFinancials.mockResolvedValueOnce({ enabled: false });
    const off = mount();
    await flush();
    expect(find(off, 'card')).toBeNull();
  });

  it('shows a failure', async () => {
    getFinancials.mockResolvedValueOnce(CARD);
    recognizeRevenue.mockRejectedValue({ body: { message: 'The open month is never stored' } });
    const element = mount();
    await flush();
    find(element, 'recognize').click();
    await flush();
    expect(find(element, 'error-message').message).toBe('The open month is never stored');
  });
});
