import { createElement } from 'lwc';
import AskReopen from 'c/askReopen';
import { expectAccessible } from 'barn/a11y';

const ASK_ID = 'a01000000000001AAA';

describe('c-ask-reopen', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('opens the quick status window for Reopen Ask on its record', async () => {
    const element = createElement('c-ask-reopen', { is: AskReopen });
    element.recordId = ASK_ID;
    document.body.appendChild(element);
    await Promise.resolve();

    const inner = element.shadowRoot.querySelector('c-giving-quick-status');
    expect(inner.action).toBe('reopenAsk');
    expect(inner.recordId).toBe(ASK_ID);
    await expectAccessible(element);
  });
});
