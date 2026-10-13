import { createElement } from 'lwc';
import DataJobHistory from 'c/dataJobHistory';
import getRecentBatches from '@salesforce/apex/ImportController.getRecentBatches';
import getUpdatePage from '@salesforce/apex/BulkUpdateController.getPage';
import getDeletePage from '@salesforce/apex/BulkDeleteController.getPage';

jest.mock('@salesforce/customPermission/Manage_BarnCRM_Settings', () => ({ default: false }), {
  virtual: true
});
jest.mock('@salesforce/customPermission/Bulk_Update_Records', () => ({ default: true }), {
  virtual: true
});
jest.mock('@salesforce/customPermission/Bulk_Delete_Records', () => ({ default: false }), {
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

describe('c-data-job-history with only the bulk update permission', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('reads only the bulk updates, never the controllers the person was not granted', async () => {
    getUpdatePage.mockResolvedValue({ allowed: true, jobs: [] });
    const element = createElement('c-data-job-history', { is: DataJobHistory });
    document.body.appendChild(element);
    await flush();
    await flush();

    expect(getRecentBatches).not.toHaveBeenCalled();
    expect(getDeletePage).not.toHaveBeenCalled();
    expect(getUpdatePage).toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('lightning-card')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="filter"]')).toBeNull();
  });
});
