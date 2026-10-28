import { createElement } from 'lwc';
import OrgOptimizer from 'c/orgOptimizer';
import getLastRun from '@salesforce/apex/HealthCheckController.getLastRun';

jest.mock('@salesforce/customPermission/Manage_BarnCRM_Settings', () => ({ default: false }), {
  virtual: true
});
jest.mock('@salesforce/customPermission/Find_And_Export_Records', () => ({ default: true }), {
  virtual: true
});
jest.mock('@salesforce/customPermission/Review_Duplicate_Suggestions', () => ({ default: false }), {
  virtual: true
});
jest.mock('@salesforce/apex/HealthCheckController.getLastRun', () => ({ default: jest.fn() }), {
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

  it('shows only the Overview and Data Quality, and reads no admin badge', async () => {
    const element = createElement('c-org-optimizer', { is: OrgOptimizer });
    document.body.appendChild(element);
    await flush();

    const tabs = Array.from(element.shadowRoot.querySelectorAll('lightning-tab')).map(
      (tab) => tab.value
    );
    expect(tabs).toEqual(['overview', 'quality']);
    const groups = element.shadowRoot.querySelector('c-barn-tool-grid').groups;
    expect(groups.flatMap((group) => group.tiles).map((tile) => tile.name)).toEqual(['quality']);
    expect(getLastRun).not.toHaveBeenCalled();
  });
});
