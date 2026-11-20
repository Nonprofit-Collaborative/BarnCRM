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
jest.mock(
  '@salesforce/apex/HealthCheckController.getLastRun',
  () => ({ default: jest.fn(() => Promise.resolve(null)) }),
  { virtual: true }
);
jest.mock('@salesforce/apex/ErrorLogController.getTile', () => ({ default: jest.fn() }), {
  virtual: true
});
import getErrorTile from '@salesforce/apex/ErrorLogController.getTile';

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('c-org-optimizer for staff with Find and Export only', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('shows only the Overview, Data Quality and Health Check, and reads no error badge', async () => {
    const element = createElement('c-org-optimizer', { is: OrgOptimizer });
    document.body.appendChild(element);
    await flush();

    const sections = Array.from(
      element.shadowRoot.querySelectorAll('lightning-vertical-navigation-item-icon')
    ).map((item) => item.name);
    expect(sections).toEqual(['overview', 'quality', 'healthCheck']);
    const show = element.shadowRoot.querySelector('lightning-combobox[data-id="show"]');
    expect(show.options.map((option) => option.value)).toEqual([
      'overview',
      'quality',
      'healthCheck'
    ]);
    const groups = element.shadowRoot.querySelector('c-barn-tool-grid').groups;
    expect(groups.flatMap((group) => group.tiles).map((tile) => tile.name)).toEqual([
      'quality',
      'healthCheck'
    ]);
    // Health Check reads for everyone who opens the page; the error count is for administrators.
    expect(getLastRun).toHaveBeenCalled();
    expect(getErrorTile).not.toHaveBeenCalledWith({ rowCount: 1 });
  });
});
