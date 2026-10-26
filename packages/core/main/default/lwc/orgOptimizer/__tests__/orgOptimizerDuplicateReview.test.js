import { createElement } from 'lwc';
import OrgOptimizer from 'c/orgOptimizer';

// A Staff or Read Only user given BarnCRM Duplicate Review, and nothing else.
jest.mock('@salesforce/customPermission/Manage_BarnCRM_Settings', () => ({ default: false }), {
  virtual: true
});
jest.mock('@salesforce/customPermission/Find_And_Export_Records', () => ({ default: false }), {
  virtual: true
});
jest.mock('@salesforce/customPermission/Review_Duplicate_Suggestions', () => ({ default: true }), {
  virtual: true
});

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('c-org-optimizer for a BarnCRM Duplicate Review holder who is not an admin', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('shows only the Overview and Duplicates', async () => {
    const element = createElement('c-org-optimizer', { is: OrgOptimizer });
    document.body.appendChild(element);
    await flush();

    const tabs = Array.from(element.shadowRoot.querySelectorAll('lightning-tab')).map(
      (tab) => tab.value
    );
    expect(tabs).toEqual(['overview', 'duplicates']);
    const names = Array.from(
      element.shadowRoot.querySelectorAll('lightning-button[data-section]')
    ).map((button) => button.dataset.section);
    expect(names).toEqual(['duplicates']);
  });
});
