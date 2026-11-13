import { createElement } from 'lwc';
import GiftDoNotThank from 'c/giftDoNotThank';
import { expectAccessible } from 'barn/a11y';

const GIFT_ID = 'a01000000000001AAA';

describe('c-gift-do-not-thank', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('opens the quick status window for Do Not Thank on its record', async () => {
    const element = createElement('c-gift-do-not-thank', { is: GiftDoNotThank });
    element.recordId = GIFT_ID;
    document.body.appendChild(element);
    await Promise.resolve();

    const inner = element.shadowRoot.querySelector('c-giving-quick-status');
    expect(inner.action).toBe('doNotThank');
    expect(inner.recordId).toBe(GIFT_ID);
    await expectAccessible(element);
  });
});
