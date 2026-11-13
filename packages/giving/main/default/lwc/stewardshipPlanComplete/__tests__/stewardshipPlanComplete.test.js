import { createElement } from 'lwc';
import StewardshipPlanComplete from 'c/stewardshipPlanComplete';
import { expectAccessible } from 'barn/a11y';

const PLAN_ID = 'a01000000000001AAA';

describe('c-stewardship-plan-complete', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('opens the quick status window for Mark Plan Complete on its record', async () => {
    const element = createElement('c-stewardship-plan-complete', { is: StewardshipPlanComplete });
    element.recordId = PLAN_ID;
    document.body.appendChild(element);
    await Promise.resolve();

    const inner = element.shadowRoot.querySelector('c-giving-quick-status');
    expect(inner.action).toBe('markPlanComplete');
    expect(inner.recordId).toBe(PLAN_ID);
    await expectAccessible(element);
  });
});
