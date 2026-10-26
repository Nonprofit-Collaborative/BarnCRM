import { createElement } from 'lwc';
import DuplicateMatching from 'c/duplicateMatching';

// Someone who reached the tab without any permission that opens an area.
jest.mock('@salesforce/customPermission/Manage_BarnCRM_Settings', () => ({ default: false }), {
  virtual: true
});
jest.mock('@salesforce/customPermission/Review_Duplicate_Suggestions', () => ({ default: false }), {
  virtual: true
});
jest.mock('@salesforce/customPermission/Manage_BarnCRM_Metadata', () => ({ default: false }), {
  virtual: true
});

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('c-duplicate-matching without access', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('says why nothing is shown, and loads no area', async () => {
    const element = createElement('c-duplicate-matching', { is: DuplicateMatching });
    document.body.appendChild(element);
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="no-access"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('lightning-tabset')).toBeNull();
    expect(element.shadowRoot.querySelector('c-duplicate-review')).toBeNull();
  });
});
