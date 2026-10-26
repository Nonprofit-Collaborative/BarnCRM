import { createElement } from 'lwc';
import DuplicateMatching from 'c/duplicateMatching';

// A BarnCRM Metadata Admin holder who is not an administrator and has no Duplicate Review.
jest.mock('@salesforce/customPermission/Manage_BarnCRM_Settings', () => ({ default: false }), {
  virtual: true
});
jest.mock('@salesforce/customPermission/Review_Duplicate_Suggestions', () => ({ default: false }), {
  virtual: true
});
jest.mock('@salesforce/customPermission/Manage_BarnCRM_Metadata', () => ({ default: true }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/MatchSourceController.getView',
  () => ({
    default: jest.fn(() => Promise.resolve({ canEdit: true, sources: [], normalizations: [] }))
  }),
  { virtual: true }
);

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('c-duplicate-matching for a Metadata Admin holder', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('shows only Matching Logic, opened', async () => {
    const element = createElement('c-duplicate-matching', { is: DuplicateMatching });
    document.body.appendChild(element);
    await flush();

    const tabs = Array.from(element.shadowRoot.querySelectorAll('lightning-tab')).map(
      (tab) => tab.value
    );
    expect(tabs).toEqual(['matchingLogic']);
    expect(element.shadowRoot.querySelector('c-match-source-manager')).not.toBeNull();
    expect(element.shadowRoot.querySelector('c-duplicate-review')).toBeNull();
  });
});
