import { createElement } from 'lwc';
import DuplicateMatching from 'c/duplicateMatching';

// An administrator: Manage BarnCRM Settings.
jest.mock('@salesforce/customPermission/Manage_BarnCRM_Settings', () => ({ default: true }), {
  virtual: true
});
jest.mock('@salesforce/customPermission/Review_Duplicate_Suggestions', () => ({ default: false }), {
  virtual: true
});

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

  it('opens on the review list', async () => {
    const element = await render();

    expect(element.shadowRoot.querySelector('lightning-tabset').activeTabValue).toBe('review');
    expect(element.shadowRoot.querySelector('c-duplicate-review')).not.toBeNull();
  });

  it('keeps an area loaded once it has been opened', async () => {
    const element = await render();

    const review = element.shadowRoot.querySelector('lightning-tab[data-id="tab-review"]');
    review.dispatchEvent(new CustomEvent('active'));
    await flush();

    expect(element.shadowRoot.querySelector('c-duplicate-review')).not.toBeNull();
  });
});
