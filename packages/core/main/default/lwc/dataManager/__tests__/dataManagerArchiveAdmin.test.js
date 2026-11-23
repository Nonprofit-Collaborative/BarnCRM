// Test wire adapters are emitted to on purpose, which is how a wired component is driven from a test.
/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { createElement } from 'lwc';
import DataManager from 'c/dataManager';
import orgOptimizerInstalled from '@salesforce/apex/DataManagerController.orgOptimizerInstalled';
import canViewArchive from '@salesforce/apex/ArchiveController.canViewArchive';

// Someone who is not a BarnCRM Admin, given BarnCRM Archive Admin and BarnCRM Bulk Delete (D-223).
jest.mock('@salesforce/customPermission/Manage_BarnCRM_Settings', () => ({ default: false }), {
  virtual: true
});
jest.mock('@salesforce/customPermission/Manage_Archive', () => ({ default: true }), {
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
  '@salesforce/apex/DataManagerController.orgOptimizerInstalled',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ArchiveController.canViewArchive',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

function tileNames(element) {
  return element.shadowRoot
    .querySelector('[data-id="tools"]')
    .groups.flatMap((group) => group.tiles)
    .map((tile) => tile.name);
}

describe('c-data-manager for a BarnCRM Archive Admin', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows Archive Rules and Archived Records but no administrator tools', async () => {
    const element = createElement('c-data-manager', { is: DataManager });
    document.body.appendChild(element);
    orgOptimizerInstalled.emit(false);
    canViewArchive.emit(true);
    await flush();

    const names = tileNames(element);
    expect(names).toEqual(expect.arrayContaining(['find', 'archive', 'archived']));
    expect(names).not.toContain('backup');
    expect(names).not.toContain('import');
  });
});
