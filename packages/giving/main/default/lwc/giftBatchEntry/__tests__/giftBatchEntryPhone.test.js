// The form factor is read once, when the component loads, so the phone case has its own file.
/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { createElement } from 'lwc';
import GiftBatchEntry from 'c/giftBatchEntry';
import { getRecord } from 'lightning/uiRecordApi';
import getBatch from '@salesforce/apex/GiftBatchController.getBatch';

jest.mock('@salesforce/client/formFactor', () => ({ __esModule: true, default: 'Small' }), {
  virtual: true
});
jest.mock('@salesforce/apex/GiftBatchController.getBatch', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/GiftBatchController.saveLines', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/GiftBatchController.postBatch', () => ({ default: jest.fn() }), {
  virtual: true
});

const BATCH_ID = 'a0B000000000001AAA';

async function settle() {
  for (let i = 0; i < 6; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
}

describe('c-gift-batch-entry on a phone', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('says batches are easier on a computer, and still shows the lines', async () => {
    getBatch.mockResolvedValue({
      id: BATCH_ID,
      posted: false,
      controlTotal: 100,
      hasPersonAccounts: false,
      canEdit: true,
      paymentMethods: [],
      lines: [{ id: 'a0C1', donorContactId: null, donorAccountId: null, amount: 100 }]
    });
    const element = createElement('c-gift-batch-entry', { is: GiftBatchEntry });
    element.recordId = BATCH_ID;
    document.body.appendChild(element);
    getRecord.emit({ id: BATCH_ID, fields: {} });
    await settle();

    const note = element.shadowRoot.querySelector('[data-id="use-computer"]');
    expect(note.textContent).toBe('c.Giving_GiftBatch_UseComputer');
    expect(element.shadowRoot.querySelectorAll('[data-field="amount"]')).toHaveLength(1);
  });
});
