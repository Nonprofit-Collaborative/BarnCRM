import { createElement } from 'lwc';
import GiftCancelPending from 'c/giftCancelPending';
import { expectAccessible } from 'barn/a11y';

const GIFT_ID = 'a01000000000001AAA';

describe('c-gift-cancel-pending', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('opens the quick status window for Cancel Pending Gift on its record', async () => {
    const element = createElement('c-gift-cancel-pending', { is: GiftCancelPending });
    element.recordId = GIFT_ID;
    document.body.appendChild(element);
    await Promise.resolve();

    const inner = element.shadowRoot.querySelector('c-giving-quick-status');
    expect(inner.action).toBe('cancelPendingGift');
    expect(inner.recordId).toBe(GIFT_ID);
    await expectAccessible(element);
  });
});
