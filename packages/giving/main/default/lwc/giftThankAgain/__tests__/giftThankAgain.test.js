import { createElement } from 'lwc';
import GiftThankAgain from 'c/giftThankAgain';
import { expectAccessible } from 'barn/a11y';

const GIFT_ID = 'a01000000000001AAA';

describe('c-gift-thank-again', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('opens the quick status window for Thank Again on its record', async () => {
    const element = createElement('c-gift-thank-again', { is: GiftThankAgain });
    element.recordId = GIFT_ID;
    document.body.appendChild(element);
    await Promise.resolve();

    const inner = element.shadowRoot.querySelector('c-giving-quick-status');
    expect(inner.action).toBe('thankAgain');
    expect(inner.recordId).toBe(GIFT_ID);
    await expectAccessible(element);
  });
});
