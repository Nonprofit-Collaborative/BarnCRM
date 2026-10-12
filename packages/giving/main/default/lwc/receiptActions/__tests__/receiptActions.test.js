import { createElement } from 'lwc';
import ReceiptActions from 'c/receiptActions';
import getGiftReceiptState from '@salesforce/apex/ReceiptController.getGiftReceiptState';
import issueReceipt from '@salesforce/apex/ReceiptController.issue';
import voidAndReissue from '@salesforce/apex/ReceiptController.voidAndReissue';

jest.mock(
  '@salesforce/apex/ReceiptController.getGiftReceiptState',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ReceiptController.issue',
  () => ({ default: jest.fn(() => Promise.resolve({ receiptNumber: 'HFH-2026-000001' })) }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ReceiptController.voidAndReissue',
  () => ({ default: jest.fn(() => Promise.resolve({ receiptNumber: 'HFH-2026-000002' })) }),
  { virtual: true }
);
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
jest.mock('@salesforce/apex', () => ({ refreshApex: jest.fn(() => Promise.resolve()) }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Giving_Receipt_IssuedMessage',
  () => ({ default: 'Receipt {0} has been issued.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Giving_Receipt_UnexpectedError',
  () => ({ default: 'That did not work.' }),
  { virtual: true }
);

const GIFT_ID = 'a00000000000001';
const DOCUMENT_ID = '069000000000001';

const ISSUED = {
  id: 'a02000000000001',
  receiptNumber: 'HFH-2026-000001',
  status: 'Issued',
  amount: 250,
  contentDocumentId: DOCUMENT_ID
};

function build() {
  const element = createElement('c-receipt-actions', { is: ReceiptActions });
  element.recordId = GIFT_ID;
  document.body.appendChild(element);
  return element;
}

function flush() {
  return Promise.resolve();
}

function byId(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

describe('c-receipt-actions', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('offers to issue a receipt when the gift has none', async () => {
    const element = build();
    getGiftReceiptState.emit({ canIssue: true, alreadyReceipted: false, receipts: [] });
    await flush();

    expect(byId(element, 'issue')).not.toBeNull();
    expect(byId(element, 'none-yet')).not.toBeNull();
    expect(byId(element, 'void-and-reissue')).toBeNull();
  });

  it('offers void and reissue once the gift is receipted, and never a plain edit', async () => {
    const element = build();
    getGiftReceiptState.emit({ canIssue: true, alreadyReceipted: true, receipts: [ISSUED] });
    await flush();

    expect(byId(element, 'void-and-reissue')).not.toBeNull();
    expect(byId(element, 'issue')).toBeNull();
  });

  it('refuses to void without a reason, and does not call the server', async () => {
    const element = build();
    const toasts = jest.fn();
    element.addEventListener('lightning__showtoast', toasts);
    getGiftReceiptState.emit({ canIssue: true, alreadyReceipted: true, receipts: [ISSUED] });
    await flush();

    byId(element, 'void-and-reissue').click();
    await flush();

    expect(voidAndReissue).not.toHaveBeenCalled();
    expect(toasts).toHaveBeenCalled();
    expect(toasts.mock.calls[0][0].detail.variant).toBe('warning');
  });

  it('issues a receipt when asked, and names it in the success message', async () => {
    const element = build();
    const toasts = jest.fn();
    element.addEventListener('lightning__showtoast', toasts);
    getGiftReceiptState.emit({ canIssue: true, alreadyReceipted: false, receipts: [] });
    await flush();

    byId(element, 'issue').click();
    await flush();
    await flush();

    expect(issueReceipt).toHaveBeenCalledWith({ giftId: GIFT_ID });
    expect(toasts.mock.calls[0][0].detail.message).toBe('Receipt HFH-2026-000001 has been issued.');
  });

  it('opens the receipt PDF in the standard file preview', async () => {
    const element = build();
    getGiftReceiptState.emit({ canIssue: true, alreadyReceipted: true, receipts: [ISSUED] });
    await flush();

    byId(element, 'view-pdf').click();

    const pageReference = mockNavigate.mock.calls[0][0];
    expect(pageReference.type).toBe('standard__namedPage');
    expect(pageReference.attributes.pageName).toBe('filePreview');
    expect(pageReference.state.selectedRecordId).toBe(DOCUMENT_ID);
  });

  it('offers no PDF link for a receipt that has no file', async () => {
    const element = build();
    getGiftReceiptState.emit({
      canIssue: true,
      alreadyReceipted: true,
      receipts: [{ ...ISSUED, contentDocumentId: null }]
    });
    await flush();

    expect(byId(element, 'view-pdf')).toBeNull();
  });

  it('shows a plain apology when the server gives no reason', async () => {
    const element = build();
    getGiftReceiptState.error({});
    await flush();

    expect(byId(element, 'load-error').textContent).toBe('That did not work.');
  });

  it('offers nothing to a user who cannot issue receipts', async () => {
    const element = build();
    getGiftReceiptState.emit({ canIssue: false, alreadyReceipted: false, receipts: [] });
    await flush();

    expect(element.shadowRoot.querySelectorAll('lightning-button')).toHaveLength(0);
  });
});
