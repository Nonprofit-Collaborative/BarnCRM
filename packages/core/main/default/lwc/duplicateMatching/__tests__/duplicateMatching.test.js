import { createElement } from 'lwc';
import DuplicateMatching from 'c/duplicateMatching';

// An administrator: Manage BarnCRM Settings, without Metadata Admin.
jest.mock('@salesforce/customPermission/Manage_BarnCRM_Settings', () => ({ default: true }), {
  virtual: true
});
jest.mock('@salesforce/customPermission/Review_Duplicate_Suggestions', () => ({ default: false }), {
  virtual: true
});
jest.mock('@salesforce/customPermission/Manage_BarnCRM_Metadata', () => ({ default: false }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/MatchSourceController.getView',
  () => ({
    default: jest.fn(() => Promise.resolve({ canEdit: false, sources: [], normalizations: [] }))
  }),
  { virtual: true }
);

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

function render() {
  const element = createElement('c-duplicate-matching', { is: DuplicateMatching });
  document.body.appendChild(element);
  return flush().then(() => element);
}

describe('c-duplicate-matching for an administrator', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('opens on the review list, and offers Matching Logic', async () => {
    const element = await render();

    const tabs = Array.from(element.shadowRoot.querySelectorAll('lightning-tab')).map(
      (tab) => tab.value
    );
    expect(tabs).toEqual(['review', 'matchingLogic']);
    expect(element.shadowRoot.querySelector('lightning-tabset').activeTabValue).toBe('review');
    expect(element.shadowRoot.querySelector('c-duplicate-review')).not.toBeNull();
    expect(element.shadowRoot.querySelector('c-match-source-manager')).toBeNull();
  });

  it('creates Matching Logic when it is first opened, and keeps the review list', async () => {
    const element = await render();

    const logic = element.shadowRoot.querySelector('lightning-tab[data-id="tab-matchingLogic"]');
    logic.dispatchEvent(new CustomEvent('active'));
    await flush();

    expect(element.shadowRoot.querySelector('c-match-source-manager')).not.toBeNull();
    expect(element.shadowRoot.querySelector('c-duplicate-review')).not.toBeNull();
  });
});
