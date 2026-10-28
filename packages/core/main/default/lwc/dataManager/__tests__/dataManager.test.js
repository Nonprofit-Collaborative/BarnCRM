import { createElement } from 'lwc';
import DataManager from 'c/dataManager';
import getMappings from '@salesforce/apex/DataManagerController.getMappings';
import BarnConfirmModal from 'c/barnConfirmModal';

jest.mock('@salesforce/label/c.Core_DataManager_OpenAria', () => ({ default: 'Open {0}' }), {
  virtual: true
});

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
jest.mock('@salesforce/customPermission/Bulk_Update_Records', () => ({ default: false }), {
  virtual: true
});
jest.mock('@salesforce/customPermission/Bulk_Delete_Records', () => ({ default: true }), {
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
jest.mock(
  '@salesforce/apex/DataManagerController.findToolStateKey',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
import findToolStateKey from '@salesforce/apex/DataManagerController.findToolStateKey';

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

  it('marks the bulk delete card destructive, with no warning bar on the page', async () => {
    const element = await render();

    const card = element.shadowRoot.querySelector('div[data-id="delete"]');
    expect(card.querySelector('lightning-button').variant).toBe('destructive-text');
    expect(element.shadowRoot.querySelector('.slds-theme_warning')).toBeNull();
    expect(element.shadowRoot.querySelector('lightning-icon')).toBeNull();
    expect(element.shadowRoot.textContent).not.toContain('c.Core_DataManager_DeleteWarning');

    // No other tool has a red button.
    const find = element.shadowRoot.querySelector('div[data-id="find"] lightning-button');
    expect(find.variant).toBe('neutral');
  });

  it('lists Delete Many Records as the last card', async () => {
    const element = await render();

    const keys = Array.from(element.shadowRoot.querySelectorAll('lightning-button[data-tab]')).map(
      (button) => button.dataset.id
    );
    expect(keys).toEqual(['import', 'find', 'optimizer', 'delete']);
  });

  it('asks before opening the delete tool, and opens Find only on Continue', async () => {
    const element = await render();
    // The key comes from Apex with the namespace's prefix; a made-up one proves it is used as is.
    findToolStateKey.emit('ns__tool');
    BarnConfirmModal.open.mockResolvedValueOnce(true);

    element.shadowRoot.querySelector('lightning-button[data-id="delete"]').click();
    await flush();

    expect(BarnConfirmModal.open).toHaveBeenCalledTimes(1);
    expect(BarnConfirmModal.open.mock.calls[0][0]).toEqual({
      size: 'small',
      label: 'c.Core_DataManager_DeleteTitle',
      message: 'c.Core_DataManager_DeleteWarning',
      confirmLabel: 'c.Core_DataManager_DeleteContinue',
      cancelLabel: 'c.Core_DataManager_DeleteCancel',
      confirmVariant: 'destructive'
    });
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Find' },
      state: { ns__tool: 'delete' }
    });
  });

  it('does nothing when the delete box is cancelled or closed', async () => {
    const element = await render();
    const button = element.shadowRoot.querySelector('lightning-button[data-id="delete"]');

    BarnConfirmModal.open.mockResolvedValueOnce(false);
    button.click();
    await flush();
    BarnConfirmModal.open.mockResolvedValueOnce(undefined);
    button.click();
    await flush();

    expect(BarnConfirmModal.open).toHaveBeenCalledTimes(2);
    expect(mockNavigate).not.toHaveBeenCalled();
  });

  it('opens Find from its card without asking', async () => {
    const element = await render();

    element.shadowRoot.querySelector('lightning-button[data-id="find"]').click();
    await flush();

    expect(BarnConfirmModal.open).not.toHaveBeenCalled();
    expect(mockNavigate).toHaveBeenLastCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Find' }
    });
  });

  it('says what an import template is above the list', async () => {
    const element = await render();
    expect(one(element, 'mappings-intro').textContent).toBe('c.Core_DataManager_MappingsIntro');
  });

  it('capitalizes every word of each Data Manager title and calls templates templates', () => {
    // The labels file itself: Jest resolves a label to its name, so read the shipped values.
    // Jest runs from the repository root (jest.config.js).
    const fs = require('fs');
    const xml = fs.readFileSync(
      'packages/core/main/default/labels/DataManager.labels-meta.xml',
      'utf8'
    );
    const values = {};
    for (const match of xml.matchAll(
      /<fullName>(\w+)<\/fullName>[\s\S]*?<value>([\s\S]*?)<\/value>/g
    )) {
      values[match[1]] = match[2];
    }
    const small = new Set(['a', 'an', 'and', 'or', 'the', 'of', 'to', 'in', 'for', 'on']);
    const titles = [
      'Title',
      'ToolsHeading',
      'ImportTitle',
      'FindTitle',
      'UpdateTitle',
      'DeleteTitle',
      'OptimizerTitle',
      'MappingsHeading',
      'SalesforceHeading'
    ];
    titles.forEach((key) => {
      const words = values[`Core_DataManager_${key}`].split(' ');
      words.forEach((word, index) => {
        if (index > 0 && small.has(word)) {
          return;
        }
        expect(`${key}: ${word[0]}`).toBe(`${key}: ${word[0].toUpperCase()}`);
      });
    });
    expect(values.Core_DataManager_MappingsHeading).toBe('Import Templates');
    Object.entries(values).forEach(([name, value]) =>
      expect(`${name}: ${/mapping/i.test(value)}`).toBe(`${name}: false`)
    );
  });

  it('shows a card for each tool the person may use', async () => {
    const element = await render();

    expect(one(element, 'import')).not.toBeNull();
    expect(one(element, 'find')).not.toBeNull();
    expect(one(element, 'update')).toBeNull();
    expect(one(element, 'delete')).not.toBeNull();
    expect(one(element, 'optimizer')).not.toBeNull();
  });

  it('names each Open button for its tool', async () => {
    const element = await render();

    const names = Array.from(element.shadowRoot.querySelectorAll('lightning-button[data-tab]')).map(
      (button) => button.ariaLabel
    );
    expect(names.length).toBeGreaterThan(1);
    names.forEach((name) => expect(name).toMatch(/^Open \S/));
    expect(new Set(names).size).toBe(names.length);
  });

  it('opens the tool tab by its API name', async () => {
    const element = await render();

    element.shadowRoot.querySelector('lightning-button[data-id="import"]').click();
    await flush();
    expect(mockNavigate).toHaveBeenLastCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Import' }
    });

    element.shadowRoot.querySelector('lightning-button[data-id="optimizer"]').click();
    await flush();
    expect(mockNavigate.mock.calls[1][0].attributes.apiName).toBe('Data_Hygiene');
  });

  it('lists the import templates, a people template as people', async () => {
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

  it('shows the unexpected-error label, not raw text, when the error has no message', async () => {
    const element = await render();
    getMappings.error({});
    await flush();
    expect(one(element, 'mappings-error').textContent).toContain('c.Core_UnexpectedError');
  });

  it('says when there are no templates, and shows a templates error', async () => {
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
