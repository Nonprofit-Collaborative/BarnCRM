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
jest.mock(
  '@salesforce/apex/AutoMergeController.getView',
  () => ({
    default: jest.fn(() => Promise.resolve({ canRun: true, running: false, runs: [] }))
  }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_DuplicateMatching_ReviewCount',
  () => ({ default: 'Review ({0})' }),
  {
    virtual: true
  }
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

  it('leaves the page name to the App Page header, with no card around the page', async () => {
    const element = await render();

    const shell = element.shadowRoot.querySelector('c-barn-page-shell');
    expect(shell.titleHidden).toBe(true);
    expect(shell.title).toBe('c.Core_DuplicateMatching_Title');
    expect(shell.purpose).toBe('c.Core_DuplicateMatching_Intro');
    expect(element.shadowRoot.querySelector('lightning-card')).toBeNull();
  });

  it('opens on the review list, and offers Matching Logic and Auto-Merge', async () => {
    const element = await render();

    const tabs = Array.from(element.shadowRoot.querySelectorAll('lightning-tab')).map(
      (tab) => tab.value
    );
    expect(tabs).toEqual(['review', 'matchingLogic', 'autoMerge']);
    expect(element.shadowRoot.querySelector('c-auto-merge-panel')).toBeNull();
    expect(element.shadowRoot.querySelector('lightning-tabset').activeTabValue).toBe('review');
    expect(element.shadowRoot.querySelector('c-duplicate-review')).not.toBeNull();
    expect(element.shadowRoot.querySelector('c-match-source-manager')).toBeNull();
  });

  it('names the Review tab with the pairs waiting, as the review list counts them', async () => {
    const element = await render();
    const tab = element.shadowRoot.querySelector('[data-id="tab-review"]');
    const review = element.shadowRoot.querySelector('c-duplicate-review');
    expect(tab.label).toBe('c.Core_DuplicateMatching_Review');

    review.dispatchEvent(new CustomEvent('countchange', { detail: { count: '50+' } }));
    await flush();
    expect(tab.label).toBe('Review (50+)');

    review.dispatchEvent(new CustomEvent('countchange', { detail: { count: '' } }));
    await flush();
    expect(tab.label).toBe('c.Core_DuplicateMatching_Review');
  });

  it('sits in the page shell with the title for screen readers only', async () => {
    const element = await render();
    const shell = element.shadowRoot.querySelector('c-barn-page-shell');
    expect(shell.titleHidden).toBe(true);
    expect(shell.title).toBe('c.Core_DuplicateMatching_Title');
    expect(shell.purpose).toBe('c.Core_DuplicateMatching_Intro');
    expect(element.shadowRoot.querySelector('lightning-card')).toBeNull();
  });

  it('creates Matching Logic when it is first opened, and keeps the review list', async () => {
    const element = await render();

    const logic = element.shadowRoot.querySelector('lightning-tab[data-id="tab-matchingLogic"]');
    logic.dispatchEvent(new CustomEvent('active'));
    await flush();

    expect(element.shadowRoot.querySelector('c-match-source-manager')).not.toBeNull();
    expect(element.shadowRoot.querySelector('c-duplicate-review')).not.toBeNull();
  });

  it('creates Auto-Merge when it is first opened', async () => {
    const element = await render();

    const autoMerge = element.shadowRoot.querySelector('lightning-tab[data-id="tab-autoMerge"]');
    expect(autoMerge.label).toBe('c.Core_AutoMerge_Tab');
    autoMerge.dispatchEvent(new CustomEvent('active'));
    await flush();

    expect(element.shadowRoot.querySelector('c-auto-merge-panel')).not.toBeNull();
  });
});
