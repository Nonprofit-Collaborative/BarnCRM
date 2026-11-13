import { createElement } from 'lwc';
import ProjectsBillingExport from 'c/projectsBillingExport';
import getProjectBilling from '@salesforce/apex/ProjectBillingController.getProjectBilling';
import exportInvoices from '@salesforce/apex/ProjectBillingController.exportInvoices';
import { downloadCsv } from 'c/findCsv';

jest.mock(
  '@salesforce/apex/ProjectBillingController.getProjectBilling',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ProjectBillingController.exportInvoices',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('c/findCsv', () => ({
  ...jest.requireActual('c/findCsv'),
  downloadCsv: jest.fn()
}));

const flush = () =>
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  new Promise((resolve) => setTimeout(resolve, 0));

function mount() {
  const element = createElement('c-projects-billing-export', { is: ProjectsBillingExport });
  document.body.appendChild(element);
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-projects-billing-export', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('exports the invoices in the range, one row per line', async () => {
    getProjectBilling.mockResolvedValue({ enabled: true, canManage: true });
    exportInvoices.mockResolvedValue([
      { name: 'INV-000001', lines: [{ amount: 300 }, { amount: 50 }] }
    ]);
    const element = mount();
    await flush();
    const include = find(element, 'include');
    include.checked = true;
    include.dispatchEvent(new CustomEvent('change'));
    find(element, 'export').click();
    await flush();
    expect(exportInvoices).toHaveBeenCalledWith(expect.objectContaining({ includeExported: true }));
    expect(downloadCsv).toHaveBeenCalledTimes(1);
    expect(downloadCsv.mock.calls[0][2]).toHaveLength(2);
    expect(find(element, 'notice')).not.toBeNull();
  });

  it('shows nothing while off or to staff, and shows a failure', async () => {
    getProjectBilling.mockResolvedValueOnce({ enabled: false, canManage: true });
    const off = mount();
    await flush();
    expect(find(off, 'card')).toBeNull();
    getProjectBilling.mockResolvedValueOnce({ enabled: true, canManage: true });
    exportInvoices.mockRejectedValue({ body: { message: 'Choose a range' } });
    const element = mount();
    await flush();
    find(element, 'export').click();
    await flush();
    expect(find(element, 'error-message').message).toBe('Choose a range');
  });
});
