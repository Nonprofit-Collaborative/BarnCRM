import { createElement } from 'lwc';
import DuplicateMatching from 'c/duplicateMatching';

// A Staff or Read Only user given BarnCRM Duplicate Review, and nothing else.
jest.mock('@salesforce/customPermission/Manage_BarnCRM_Settings', () => ({ default: false }), {
  virtual: true
});
jest.mock('@salesforce/customPermission/Review_Duplicate_Suggestions', () => ({ default: true }), {
  virtual: true
});

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('c-duplicate-matching for a BarnCRM Duplicate Review holder who is not an admin', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('shows the review list, which reads it read-only', async () => {
    const element = createElement('c-duplicate-matching', { is: DuplicateMatching });
    document.body.appendChild(element);
    await flush();

    const tabs = Array.from(element.shadowRoot.querySelectorAll('lightning-tab')).map(
      (tab) => tab.value
    );
    expect(tabs).toEqual(['review']);
    expect(element.shadowRoot.querySelector('c-duplicate-review')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="no-access"]')).toBeNull();
  });
});
