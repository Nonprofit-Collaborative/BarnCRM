import { createElement } from 'lwc';
import ProjectsInvoiceBuilder from 'c/projectsInvoiceBuilder';
import getProjectBilling from '@salesforce/apex/ProjectBillingController.getProjectBilling';
import buildInvoice from '@salesforce/apex/ProjectBillingController.buildInvoice';

jest.mock(
  '@salesforce/apex/ProjectBillingController.getProjectBilling',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ProjectBillingController.buildInvoice',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);

const flush = () =>
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  new Promise((resolve) => setTimeout(resolve, 0));

function mount() {
  const element = createElement('c-projects-invoice-builder', { is: ProjectsInvoiceBuilder });
  element.recordId = 'a01000000000001AAA';
  document.body.appendChild(element);
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-projects-invoice-builder', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('builds a Draft for the period chosen', async () => {
    getProjectBilling.mockResolvedValue({
      enabled: true,
      canManage: true,
      billingType: 'Fixed Fee'
    });
    buildInvoice.mockResolvedValue('a02000000000001AAA');
    const element = mount();
    await flush();
    const start = find(element, 'start');
    start.value = '2026-10-01';
    start.dispatchEvent(new CustomEvent('change'));
    find(element, 'build').click();
    await flush();
    expect(buildInvoice).toHaveBeenCalledWith(
      expect.objectContaining({ projectId: 'a01000000000001AAA', periodStart: '2026-10-01' })
    );
  });

  it('shows a refusal in words', async () => {
    getProjectBilling.mockResolvedValue({ enabled: true, canManage: true, billingType: null });
    buildInvoice.mockRejectedValue({ body: { message: 'Nothing to invoice' } });
    const element = mount();
    await flush();
    find(element, 'build').click();
    await flush();
    expect(find(element, 'error-message').message).toBe('Nothing to invoice');
  });

  it('shows nothing while off, to staff or on a project that is not billed', async () => {
    for (const billing of [
      { enabled: false, canManage: true },
      { enabled: true, canManage: false },
      { enabled: true, canManage: true, billingType: 'Not Billed' }
    ]) {
      getProjectBilling.mockResolvedValueOnce(billing);
      const element = mount();
      // eslint-disable-next-line no-await-in-loop
      await flush();
      expect(find(element, 'card')).toBeNull();
    }
  });
});
