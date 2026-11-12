import { createElement } from 'lwc';
import ProjectsInvoiceActions from 'c/projectsInvoiceActions';
import getInvoiceActions from '@salesforce/apex/ProjectBillingController.getInvoiceActions';
import sendInvoice from '@salesforce/apex/ProjectBillingController.sendInvoice';
import markPaid from '@salesforce/apex/ProjectBillingController.markPaid';
import voidInvoice from '@salesforce/apex/ProjectBillingController.voidInvoice';
import printInvoice from '@salesforce/apex/ProjectBillingController.printInvoice';
import sendPaymentLink from '@salesforce/apex/ProjectBillingController.sendPaymentLink';

jest.mock(
  '@salesforce/apex/ProjectBillingController.getInvoiceActions',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/ProjectBillingController.sendInvoice', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ProjectBillingController.markPaid', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ProjectBillingController.voidInvoice', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/ProjectBillingController.printInvoice',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/apex/ProjectBillingController.sendPaymentLink',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const INVOICE = 'a02000000000001AAA';
const flush = () =>
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  new Promise((resolve) => setTimeout(resolve, 0));

function mount() {
  const element = createElement('c-projects-invoice-actions', { is: ProjectsInvoiceActions });
  element.recordId = INVOICE;
  document.body.appendChild(element);
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-projects-invoice-actions', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('sends a Draft and then offers Mark Paid', async () => {
    getInvoiceActions
      .mockResolvedValueOnce({ canManage: true, status: 'Draft' })
      .mockResolvedValueOnce({ canManage: true, status: 'Sent', balance: 100, online: false });
    sendInvoice.mockResolvedValue();
    const element = mount();
    await flush();
    expect(find(element, 'mark-paid')).toBeNull();
    find(element, 'send').click();
    await flush();
    expect(sendInvoice).toHaveBeenCalledWith({ invoiceId: INVOICE });
    expect(find(element, 'mark-paid')).not.toBeNull();
    expect(find(element, 'pay-link')).toBeNull();
  });

  it('marks paid on the date chosen and sends a payment link with its message', async () => {
    getInvoiceActions.mockResolvedValue({
      canManage: true,
      status: 'Sent',
      balance: 100,
      online: true
    });
    markPaid.mockResolvedValue();
    sendPaymentLink.mockResolvedValue('Payment link emailed to pat@example.org.');
    const element = mount();
    await flush();
    const date = find(element, 'paid-date');
    date.value = '2026-11-01';
    date.dispatchEvent(new CustomEvent('change'));
    find(element, 'mark-paid').click();
    await flush();
    expect(markPaid).toHaveBeenCalledWith({ invoiceId: INVOICE, paidDate: '2026-11-01' });
    find(element, 'pay-link').click();
    await flush();
    expect(find(element, 'notice').message).toBe('Payment link emailed to pat@example.org.');
  });

  it('asks before voiding, prints, and shows a failure', async () => {
    getInvoiceActions.mockResolvedValue({ canManage: true, status: 'Paid' });
    voidInvoice.mockResolvedValue();
    printInvoice.mockRejectedValue({ body: { message: 'No access' } });
    const element = mount();
    await flush();
    find(element, 'void').click();
    await flush();
    expect(find(element, 'void-confirm')).not.toBeNull();
    find(element, 'void-yes').click();
    await flush();
    expect(voidInvoice).toHaveBeenCalledWith({ invoiceId: INVOICE });
    find(element, 'print').click();
    await flush();
    expect(find(element, 'error-message').message).toBe('No access');
  });

  it('shows nothing to people who cannot manage projects', async () => {
    getInvoiceActions.mockResolvedValue({ canManage: false, status: 'Sent' });
    const element = mount();
    await flush();
    expect(find(element, 'card')).toBeNull();
  });
});
