import { createElement } from 'lwc';
import Toast from 'lightning/toast';
import GiftRefund from 'c/giftRefund';
import getGiftSummary from '@salesforce/apex/GiftController.getGiftSummary';
import refundGift from '@salesforce/apex/GiftController.refund';
import writeOffGift from '@salesforce/apex/GiftController.writeOff';

jest.mock(
  '@salesforce/apex/GiftController.getGiftSummary',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/GiftController.refund',
  () => ({ default: jest.fn(() => Promise.resolve('a01000000000001')) }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/GiftController.writeOff',
  () => ({ default: jest.fn(() => Promise.resolve('a01000000000002')) }),
  { virtual: true }
);

const GIFT_ID = 'a00000000000001';

function build() {
  const element = createElement('c-gift-refund', { is: GiftRefund });
  element.recordId = GIFT_ID;
  document.body.appendChild(element);
  return element;
}

function find(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

function flush() {
  return Promise.resolve();
}

describe('c-gift-refund', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('offers what is left of the gift as the amount going back', async () => {
    const element = build();
    getGiftSummary.emit({ remainingAmount: 150, fullyReversed: false });
    await flush();

    expect(find(element, 'amount').value).toBe(150);
    expect(find(element, 'remaining')).not.toBeNull();
  });

  it('asks for a reason before it records anything', async () => {
    const element = build();
    getGiftSummary.emit({ remainingAmount: 150, fullyReversed: false });
    await flush();

    const toast = jest.spyOn(Toast, 'show');
    find(element, 'confirm').click();
    await flush();

    expect(refundGift).not.toHaveBeenCalled();
    expect(toast).toHaveBeenCalled();
    expect(toast.mock.calls[0][0].variant).toBe('error');
  });

  it('records a refund of the amount David typed', async () => {
    const element = build();
    getGiftSummary.emit({ remainingAmount: 250, fullyReversed: false });
    await flush();

    find(element, 'amount').dispatchEvent(new CustomEvent('change', { detail: { value: 100 } }));
    find(element, 'reason').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Donor asked for it back' } })
    );
    find(element, 'confirm').click();
    await flush();
    await flush();

    expect(refundGift).toHaveBeenCalledWith({
      giftId: GIFT_ID,
      amount: 100,
      reason: 'Donor asked for it back'
    });
    expect(writeOffGift).not.toHaveBeenCalled();
  });

  it('writes off what is left, with no amount to type', async () => {
    const element = build();
    getGiftSummary.emit({ remainingAmount: 500, fullyReversed: false });
    await flush();

    find(element, 'mode').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'writeOff' } })
    );
    await flush();
    expect(find(element, 'amount')).toBeNull();

    find(element, 'reason').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Never paid' } })
    );
    find(element, 'confirm').click();
    await flush();
    await flush();

    expect(writeOffGift).toHaveBeenCalledWith({
      giftId: GIFT_ID,
      reason: 'Never paid'
    });
    expect(refundGift).not.toHaveBeenCalled();
  });

  it('shows the message the server sent when a refund is refused', async () => {
    refundGift.mockImplementationOnce(() =>
      Promise.reject({ body: { message: 'This refund is larger than the amount left.' } })
    );
    const element = build();
    getGiftSummary.emit({ remainingAmount: 50, fullyReversed: false });
    await flush();

    const toast = jest.spyOn(Toast, 'show');
    find(element, 'reason').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Too much' } })
    );
    find(element, 'confirm').click();
    await flush();
    await flush();

    expect(toast).toHaveBeenCalled();
    expect(toast.mock.calls[0][0].label).toContain('larger than the amount left');
  });

  it('says so when the gift cannot be read', async () => {
    const element = build();
    getGiftSummary.error({ message: 'That gift could not be found.' });
    await flush();

    expect(find(element, 'load-error').textContent).toContain('could not be found');
  });
});
