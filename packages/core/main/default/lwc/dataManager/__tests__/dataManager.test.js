import { createElement } from 'lwc';
import DataManager from 'c/dataManager';
import getMappings from '@salesforce/apex/DataManagerController.getMappings';
import BarnConfirmModal from 'c/barnConfirmModal';

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

function tiles(element, id = 'tools') {
  return one(element, id).groups.flatMap((group) => group.tiles);
}

function select(element, name) {
  one(element, 'tools').dispatchEvent(new CustomEvent('select', { detail: { name } }));
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

  it('leaves the page name to the App Page header, and leads with the purpose', async () => {
    const element = await render();

    const shell = one(element, 'shell');
    expect(shell.titleHidden).toBe(true);
    expect(shell.title).toBe('c.Core_DataManager_Title');
    expect(shell.purpose).toBe('c.Core_DataManager_Intro');
    expect(shell.iconName).toBeUndefined();
  });

  it('keeps the longer help in About This Tool, remembered per browser', async () => {
    const element = await render();

    expect(one(element, 'shell').helpStorageKey).toBe('dataManager');
    const help = one(element, 'help').textContent;
    expect(help).toContain('c.Core_DataManager_HelpChange');
    expect(help).toContain('c.Core_DataManager_HelpDelete');
  });

  it('groups the tiles, with Delete Many Records last and alone under Careful', async () => {
    const element = await render();

    const groups = one(element, 'tools').groups;
    expect(groups.map((group) => group.label)).toEqual([
      'c.Core_DataManager_GroupBringIn',
      'c.Core_DataManager_GroupFindChange',
      'c.Core_DataManager_GroupCheck',
      'c.Core_DataManager_GroupCareful'
    ]);
    expect(groups[3].tiles.map((tile) => tile.name)).toEqual(['delete']);
    tiles(element).forEach((tile) => {
      expect(tile.iconName).toMatch(/^standard:\w+$/);
      expect(tile.description).toBeTruthy();
    });
  });

  it('shows a tile for each tool the person may use', async () => {
    const element = await render();

    // Bulk Update Records is off in this test, so there is no Update Many Records tile.
    expect(tiles(element).map((tile) => tile.name)).toEqual([
      'import',
      'find',
      'optimizer',
      'delete'
    ]);
  });

  it('has no Open buttons and no warning bar: the warning lives in the confirm box', async () => {
    const element = await render();

    expect(element.shadowRoot.querySelector('lightning-button[data-tab]')).toBeNull();
    expect(element.shadowRoot.querySelector('.slds-theme_warning')).toBeNull();
    expect(element.shadowRoot.textContent).not.toContain('c.Core_DataManager_DeleteWarning');
  });

  it('asks before opening the delete tool, and opens Find only on Continue', async () => {
    const element = await render();
    // The key comes from Apex with the namespace's prefix; a made-up one proves it is used as is.
    findToolStateKey.emit('ns__tool');
    BarnConfirmModal.open.mockResolvedValueOnce(true);

    select(element, 'delete');
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

    BarnConfirmModal.open.mockResolvedValueOnce(false);
    select(element, 'delete');
    await flush();
    BarnConfirmModal.open.mockResolvedValueOnce(undefined);
    select(element, 'delete');
    await flush();

    expect(BarnConfirmModal.open).toHaveBeenCalledTimes(2);
    expect(mockNavigate).not.toHaveBeenCalled();
  });

  it('opens Find from its tile without asking', async () => {
    const element = await render();

    select(element, 'find');
    await flush();

    expect(BarnConfirmModal.open).not.toHaveBeenCalled();
    expect(mockNavigate).toHaveBeenLastCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Find' }
    });
  });

  it('opens Find with the Bulk Update note from the Update Many Records tile', async () => {
    const element = await render();
    findToolStateKey.emit('ns__tool');

    select(element, 'update');
    await flush();

    expect(BarnConfirmModal.open).not.toHaveBeenCalled();
    expect(mockNavigate).toHaveBeenLastCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Find' },
      state: { ns__tool: 'update' }
    });
  });

  it('opens the tool tab by its API name, and ignores a name it does not know', async () => {
    const element = await render();

    select(element, 'import');
    await flush();
    expect(mockNavigate).toHaveBeenLastCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Import' }
    });

    select(element, 'optimizer');
    await flush();
    expect(mockNavigate.mock.calls[1][0].attributes.apiName).toBe('Data_Hygiene');

    select(element, 'nothing');
    await flush();
    expect(mockNavigate).toHaveBeenCalledTimes(2);
  });

  it('says in one line what an import template is, with Learn More', async () => {
    const element = await render();
    expect(one(element, 'mappings-intro').textContent).toBe('c.Core_DataManager_MappingsIntro');
    expect(one(element, 'mappings-help').learnMoreUrl).toMatch(/admin-guide\/data-manager\.md$/);
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
      'GroupBringIn',
      'GroupFindChange',
      'GroupCheck',
      'GroupCareful',
      'ImportTitle',
      'FindTitle',
      'UpdateTitle',
      'DeleteTitle',
      'OptimizerTitle',
      'MappingsHeading',
      'MappingsEmpty',
      'CreateTemplate',
      'SalesforceHeading',
      'WeeklyExport',
      'RecycleBin',
      'DataImportWizard'
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

  it('keeps each tile line to 12 words or fewer', () => {
    const fs = require('fs');
    const xml = fs.readFileSync(
      'packages/core/main/default/labels/DataManager.labels-meta.xml',
      'utf8'
    );
    const lines = [
      'ImportText',
      'FindText',
      'UpdateText',
      'DeleteText',
      'OptimizerText',
      'WeeklyExportText',
      'RecycleBinText',
      'DataImportWizardText'
    ];
    lines.forEach((key) => {
      const match = xml.match(
        new RegExp(`<fullName>Core_DataManager_${key}</fullName>[\\s\\S]*?<value>([^<]*)</value>`)
      );
      expect(`${key}: ${match[1].split(' ').length <= 12}`).toBe(`${key}: true`);
    });
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
    expect(one(element, 'mappings-empty')).toBeNull();
  });

  it('shows the unexpected-error label, not raw text, when the error has no message', async () => {
    const element = await render();
    getMappings.error({});
    await flush();
    expect(one(element, 'mappings-error').textContent).toContain('c.Core_UnexpectedError');
  });

  it('shows an empty state that opens Import, and a templates error', async () => {
    const element = await render();
    getMappings.emit([]);
    await flush();

    const empty = one(element, 'mappings-empty');
    expect(empty.illustration).toBe('no-data');
    expect(empty.heading).toBe('c.Core_DataManager_MappingsEmpty');
    expect(empty.message).toBe('c.Core_DataManager_MappingsEmptyHint');
    one(element, 'create-template').click();
    expect(mockNavigate).toHaveBeenLastCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Import' }
    });

    getMappings.error({ message: 'No access' });
    await flush();
    expect(one(element, 'mappings-error')).not.toBeNull();
  });

  it("includes the job history and Salesforce's own tools as new-tab tiles", async () => {
    const element = await render();

    expect(element.shadowRoot.querySelector('c-data-job-history')).not.toBeNull();
    const salesforce = one(element, 'salesforce-tools');
    expect(salesforce.groups[0].label).toBe('c.Core_DataManager_SalesforceHeading');
    const links = tiles(element, 'salesforce-tools');
    expect(links.map((tile) => tile.name)).toEqual(['export', 'recycle', 'wizard']);
    links.forEach((tile) => {
      expect(tile.newTab).toBe(true);
      expect(tile.href).toMatch(/^\/lightning\//);
    });
  });
});
