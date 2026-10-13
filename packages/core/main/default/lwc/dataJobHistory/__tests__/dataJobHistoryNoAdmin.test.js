import { createElement } from 'lwc';
import DataJobHistory from 'c/dataJobHistory';
import getRecentBatches from '@salesforce/apex/ImportController.getRecentBatches';
import getUpdatePage from '@salesforce/apex/BulkUpdateController.getPage';
import getDeletePage from '@salesforce/apex/BulkDeleteController.getPage';

jest.mock('@salesforce/customPermission/Manage_BarnCRM_Settings', () => ({ default: false }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.getRecentBatches', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkUpdateController.getPage', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkDeleteController.getPage', () => ({ default: jest.fn() }), {
  virtual: true
});

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('c-data-job-history without Manage BarnCRM Settings', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists bulk jobs but never reads imports', async () => {
    getUpdatePage.mockResolvedValue({ allowed: true, jobs: [] });
    getDeletePage.mockResolvedValue({ allowed: false, jobs: [] });
    const element = createElement('c-data-job-history', { is: DataJobHistory });
    document.body.appendChild(element);
    await flush();
    await flush();

    expect(getRecentBatches).not.toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('lightning-card')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="filter"]')).toBeNull();
  });
});
