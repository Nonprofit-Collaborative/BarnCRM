import { createElement } from 'lwc';
import OrgOptimizer from 'c/orgOptimizer';

jest.mock('@salesforce/customPermission/Manage_BarnCRM_Settings', () => ({ default: false }), {
  virtual: true
});
jest.mock('@salesforce/customPermission/Find_And_Export_Records', () => ({ default: true }), {
  virtual: true
});
jest.mock('@salesforce/customPermission/Review_Duplicate_Suggestions', () => ({ default: false }), {
  virtual: true
});

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('c-org-optimizer for staff with Find and Export only', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('shows only the Overview and Data quality', async () => {
    const element = createElement('c-org-optimizer', { is: OrgOptimizer });
    document.body.appendChild(element);
    await flush();

    const tabs = Array.from(element.shadowRoot.querySelectorAll('lightning-tab')).map(
      (tab) => tab.value
    );
    expect(tabs).toEqual(['overview', 'quality']);
    const names = Array.from(
      element.shadowRoot.querySelectorAll('lightning-button[data-section]')
    ).map((button) => button.dataset.section);
    expect(names).toEqual(['quality']);
  });
});
