import { createElement } from 'lwc';
import DataManager from 'c/dataManager';
import getMappings from '@salesforce/apex/DataManagerController.getMappings';

const mockNavigate = jest.fn();
jest.mock(
  'lightning/navigation',
  () => {
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) =>
      class extends Base {
        [Navigate](...args) {
          mockNavigate(...args);
        }
      };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin, CurrentPageReference: null, __esModule: true };
  },
  { virtual: true }
);
jest.mock('@salesforce/customPermission/Manage_BarnCRM_Settings', () => ({ default: true }), {
  virtual: true
});
jest.mock('@salesforce/customPermission/Find_And_Export_Records', () => ({ default: true }), {
  virtual: true
});
jest.mock('@salesforce/customPermission/Bulk_Update_Records', () => ({ default: true }), {
  virtual: true
});
jest.mock('@salesforce/customPermission/Bulk_Delete_Records', () => ({ default: false }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/DataManagerController.getMappings',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

function one(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

async function render() {
  const element = createElement('c-data-manager', { is: DataManager });
  document.body.appendChild(element);
  await flush();
  return element;
}

describe('c-data-manager', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows a card for each tool the person may use', async () => {
    const element = await render();

    expect(one(element, 'import')).not.toBeNull();
    expect(one(element, 'find')).not.toBeNull();
    expect(one(element, 'update')).not.toBeNull();
    expect(one(element, 'delete')).toBeNull();
    expect(one(element, 'optimizer')).not.toBeNull();
  });

  it('opens the tool tab by its API name', async () => {
    const element = await render();

    element.shadowRoot.querySelector('lightning-button[data-id="import"]').click();
    expect(mockNavigate).toHaveBeenLastCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Import' }
    });

    element.shadowRoot.querySelector('lightning-button[data-id="optimizer"]').click();
    expect(mockNavigate.mock.calls[1][0].attributes.apiName).toBe('Data_Hygiene');
  });

  it('lists the import mappings, a people mapping as people', async () => {
    const element = await render();
    getMappings.emit([
      { id: 'a01', name: 'Generic contact list', isRecurring: false },
      {
        id: 'a02',
        name: 'Program sessions',
        targetObject: 'Session__c',
        isRecurring: true,
        sourceName: 'Monthly export',
        lastImportDate: '2026-10-01'
      }
    ]);
    await flush();

    const table = one(element, 'mappings');
    expect(table.data).toHaveLength(2);
    expect(table.data[0].loads).toBe('c.Core_DataManager_LoadsPeople');
    expect(table.data[1].loads).toBe('Session__c');
  });

  it('says when there are no mappings, and shows a mappings error', async () => {
    const element = await render();
    getMappings.emit([]);
    await flush();
    expect(one(element, 'mappings-empty')).not.toBeNull();

    getMappings.error({ message: 'No access' });
    await flush();
    expect(one(element, 'mappings-error')).not.toBeNull();
  });

  it('includes the job history and links to Salesforce tools', async () => {
    const element = await render();

    expect(element.shadowRoot.querySelector('c-data-job-history')).not.toBeNull();
    expect(one(element, 'salesforce-links').querySelectorAll('a')).toHaveLength(3);
  });
});
