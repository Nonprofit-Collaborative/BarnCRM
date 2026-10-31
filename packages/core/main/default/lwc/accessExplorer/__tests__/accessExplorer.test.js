import { createElement } from 'lwc';
import AccessExplorer from 'c/accessExplorer';
import searchPeople from '@salesforce/apex/AccessExplorerController.searchPeople';
import searchPermissionSets from '@salesforce/apex/AccessExplorerController.searchPermissionSets';
import getAccess from '@salesforce/apex/AccessExplorerController.getAccess';
import getFieldAccess from '@salesforce/apex/AccessExplorerController.getFieldAccess';
import getObjectAccess from '@salesforce/apex/AccessExplorerController.getObjectAccess';
import getPeopleWithAccess from '@salesforce/apex/AccessExplorerController.getPeopleWithAccess';
import getOverview from '@salesforce/apex/AccessExplorerController.getOverview';
import listObjects from '@salesforce/apex/DataDictionaryController.listObjects';
import describeObject from '@salesforce/apex/DataDictionaryController.describeObject';

jest.mock(
  '@salesforce/apex/AccessExplorerController.searchPeople',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/apex/AccessExplorerController.searchPermissionSets',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/AccessExplorerController.getAccess', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/AccessExplorerController.getFieldAccess',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/AccessExplorerController.getObjectAccess',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/AccessExplorerController.getPeopleWithAccess',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/AccessExplorerController.getOverview', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/DataDictionaryController.describeObject',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/DataDictionaryController.listObjects',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock('@salesforce/label/c.Core_AccessExplorer_Yes', () => ({ default: 'Yes' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_AccessExplorer_Always', () => ({ default: 'Always' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_AccessExplorer_Downloaded',
  () => ({ default: 'Downloaded {0} rows.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_AccessExplorer_ModifyAllDataNote',
  () => ({ default: '{0} gives Modify All Data.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_AccessExplorer_Truncated',
  () => ({ default: 'More than {0} give access.' }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Core_AccessExplorer_KindGroup', () => ({ default: 'Group' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_AccessExplorer_KindProfile', () => ({ default: 'Profile' }), {
  virtual: true
});

const SOURCES = [
  { id: '0PS1', label: 'System Administrator', kind: 'profile', modifyAllData: true },
  { id: '0PS2', label: 'Team Member', kind: 'group', through: 'BarnCRM Staff' }
];
const ACCESS = {
  id: '005A',
  label: 'Pat Doe',
  detail: 'Standard User',
  isActive: false,
  sources: SOURCES,
  objects: [
    {
      name: 'Relationship__c',
      label: 'Relationship',
      read: true,
      edit: true,
      grantedBy: 'Team Member (through BarnCRM Staff)'
    }
  ]
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));
const all = (element, selector) => [...element.shadowRoot.querySelectorAll(selector)];
const one = (element, selector) => element.shadowRoot.querySelector(selector);
const byId = (element, id) => one(element, `[data-id="${id}"]`);

async function render() {
  const element = createElement('c-access-explorer', { is: AccessExplorer });
  document.body.appendChild(element);
  listObjects.emit([{ value: 'Relationship__c', label: 'Relationship', isDefault: true }]);
  await flush();
  return element;
}

async function choose(element, name, value) {
  byId(element, name).dispatchEvent(new CustomEvent('change', { detail: { value } }));
  await flush();
  await flush();
}

async function type(element, value) {
  const search = byId(element, 'search');
  search.value = value;
  search.dispatchEvent(new CustomEvent('change'));
  // The search waits for a pause in typing.
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  await new Promise((resolve) => setTimeout(resolve, 350));
  await flush();
}

/** The text of the last downloaded file, without its byte-order mark. */
function readCsv(blob) {
  return new Promise((resolve) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result).replace(String.fromCharCode(0xfeff), ''));
    reader.readAsText(blob);
  });
}

describe('c-access-explorer', () => {
  let csv;
  let click;

  beforeEach(() => {
    csv = undefined;
    URL.createObjectURL = jest.fn((blob) => {
      csv = blob;
      return 'blob:x';
    });
    URL.revokeObjectURL = jest.fn();
    click = jest.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    click.mockRestore();
    jest.clearAllMocks();
  });

  it('starts on By Person or Permission Set and asks for a choice', async () => {
    const element = await render();

    expect(byId(element, 'view').value).toBe('subject');
    expect(byId(element, 'look-up').value).toBe('person');
    expect(byId(element, 'choose-subject')).not.toBeNull();
  });

  it('searches only from two letters, and says when nothing matches', async () => {
    searchPeople.mockResolvedValue([]);
    const element = await render();

    await type(element, 'P');
    expect(searchPeople).not.toHaveBeenCalled();

    await type(element, 'Pa');
    expect(searchPeople).toHaveBeenCalledWith({ term: 'Pa' });
    expect(byId(element, 'no-matches')).not.toBeNull();
  });

  it('shows a person with their sources, notes and object access, then field access', async () => {
    searchPeople.mockResolvedValue([
      { id: '005A', label: 'Pat Doe', detail: 'Standard User', isActive: false }
    ]);
    getAccess.mockResolvedValue(ACCESS);
    getFieldAccess.mockResolvedValue([
      { name: 'Name', label: 'Relationship Number', always: true },
      { name: 'Description__c', label: 'Description', read: true, grantedBy: 'Team Member' }
    ]);
    const element = await render();
    await type(element, 'Pat');

    const result = all(element, '[data-id="results"] lightning-button')[0];
    expect(result.label).toBe('Pat Doe, Standard User, c.Core_AccessExplorer_Inactive');
    result.click();
    await flush();
    await flush();

    expect(getAccess).toHaveBeenCalledWith({ subjectId: '005A' });
    expect(byId(element, 'subject').textContent).toBe(
      'Pat Doe (Standard User, c.Core_AccessExplorer_Inactive)'
    );
    expect(all(element, '[data-id="all-data"]').map((note) => note.textContent)).toEqual([
      'System Administrator gives Modify All Data.'
    ]);
    const sources = byId(element, 'sources').data;
    expect(sources.map((row) => [row.label, row.kindLabel, row.through])).toEqual([
      ['System Administrator', 'Profile', undefined],
      ['Team Member', 'Group', 'BarnCRM Staff']
    ]);
    const objects = byId(element, 'objects').data;
    expect(objects[0]).toMatchObject({ readText: 'Yes', editText: 'Yes', createText: '' });

    await choose(element, 'field-object', 'Relationship__c');
    expect(getFieldAccess).toHaveBeenCalledWith({
      subjectId: '005A',
      objectName: 'Relationship__c'
    });
    const fields = byId(element, 'fields').data;
    expect(fields.map((row) => row.readText)).toEqual(['Always', 'Yes']);
  });

  it('looks up a permission set instead of a person', async () => {
    searchPermissionSets.mockResolvedValue([
      { id: '0PS2', label: 'Team Member', detail: 'group', isActive: true }
    ]);
    const element = await render();

    await choose(element, 'look-up', 'set');
    await type(element, 'Team');

    expect(searchPermissionSets).toHaveBeenCalledWith({ term: 'Team' });
    expect(all(element, '[data-id="results"] lightning-button')[0].label).toBe(
      'Team Member, Group'
    );
  });

  it('lists who gives access to a kind of record and pages its people', async () => {
    describeObject.mockResolvedValue({
      fields: [{ fieldName: 'Description__c', fieldLabel: 'Description' }]
    });
    getObjectAccess.mockResolvedValue({
      truncated: true,
      mayMissPeople: true,
      grants: [{ id: '0PS2', label: 'Team Member', kind: 'group', read: true, activePeople: 3 }]
    });
    getPeopleWithAccess
      .mockResolvedValueOnce({
        rows: [{ name: '005A', label: 'Ann', read: true, grantedBy: 'Team Member' }],
        hasMore: true,
        afterName: 'Ann',
        afterId: '005A'
      })
      .mockResolvedValueOnce({
        rows: [{ name: '005B', label: 'Bo', read: true, grantedBy: 'Team Member' }],
        hasMore: false
      });
    const element = await render();
    await choose(element, 'view', 'object');
    expect(byId(element, 'choose-object')).not.toBeNull();

    await choose(element, 'object', 'Relationship__c');

    expect(getObjectAccess).toHaveBeenCalledWith({
      objectName: 'Relationship__c',
      fieldName: null
    });
    expect(byId(element, 'field').options.map((option) => option.value)).toEqual([
      '',
      'Description__c'
    ]);
    expect(byId(element, 'truncated').textContent).toBe('More than 2,000 give access.');
    expect(byId(element, 'grants').data[0]).toMatchObject({ kindLabel: 'Group', activePeople: 3 });
    expect(byId(element, 'grants').columns).toHaveLength(9);
    expect(byId(element, 'may-miss-people').textContent).toBe(
      'c.Core_AccessExplorer_MayMissPeople'
    );

    byId(element, 'show-more').click();
    await flush();
    await flush();

    expect(getPeopleWithAccess).toHaveBeenLastCalledWith({
      objectName: 'Relationship__c',
      fieldName: null,
      afterName: 'Ann',
      afterId: '005A'
    });
    expect(byId(element, 'people').data.map((row) => row.label)).toEqual(['Ann', 'Bo']);
    expect(byId(element, 'show-more')).toBeNull();
  });

  it('says when a field cannot be restricted, and shows read and edit for a field', async () => {
    describeObject.mockResolvedValue({ fields: [] });
    getObjectAccess
      .mockResolvedValueOnce({ grants: [] })
      .mockResolvedValueOnce({ always: true, grants: [] })
      .mockResolvedValueOnce({
        grants: [{ id: '0PS9', label: 'Set', kind: 'permissionSet', read: true }]
      });
    getPeopleWithAccess.mockResolvedValue({ rows: [], hasMore: false });
    const element = await render();
    await choose(element, 'view', 'object');
    await choose(element, 'object', 'Relationship__c');

    await choose(element, 'field', 'Name');
    expect(byId(element, 'always')).not.toBeNull();
    expect(byId(element, 'grants')).toBeNull();

    await choose(element, 'field', 'Description__c');
    expect(byId(element, 'grants').columns.map((column) => column.fieldName)).toEqual([
      'label',
      'kindLabel',
      'readText',
      'editText',
      'activePeople'
    ]);
    expect(byId(element, 'may-miss-people')).toBeNull();
  });

  it('shows BarnCRM permission sets and the Tab Access Check, and downloads the table', async () => {
    getOverview.mockResolvedValue({
      sets: [
        {
          id: '0PS5',
          label: 'BarnCRM Admin',
          name: 'BarnCRM_Admin',
          kind: 'permissionSet',
          activePeople: 2
        }
      ],
      tabAccessCheckScheduled: false
    });
    const element = await render();
    await choose(element, 'view', 'barncrm');

    expect(getOverview).toHaveBeenCalledTimes(1);
    expect(byId(element, 'barncrm').data[0]).toMatchObject({
      label: 'BarnCRM Admin',
      activePeople: 2
    });
    expect(byId(element, 'tab-check').textContent).toBe(
      'c.Core_AccessExplorer_TabCheckNotScheduled'
    );

    one(element, 'lightning-button[data-table="barncrm"]').click();
    await flush();
    const text = await readCsv(csv);
    expect(text).toContain('BarnCRM Admin');
    expect(byId(element, 'notice').textContent).toBe('Downloaded 1 rows.');

    await choose(element, 'view', 'subject');
    await choose(element, 'view', 'barncrm');
    expect(getOverview).toHaveBeenCalledTimes(1);
  });

  it('offers Compare Two and the Modify All Report as views', async () => {
    const element = await render();

    expect(byId(element, 'view').options.map((option) => option.value)).toEqual([
      'subject',
      'object',
      'barncrm',
      'compare',
      'modifyAll'
    ]);
    expect(byId(element, 'compare')).toBeNull();

    await choose(element, 'view', 'compare');
    expect(byId(element, 'compare')).not.toBeNull();
    expect(byId(element, 'subject-view')).toBeNull();

    await choose(element, 'view', 'modifyAll');
    expect(byId(element, 'modify-all')).not.toBeNull();
    expect(byId(element, 'compare')).toBeNull();
  });

  it('shows the server message when a read fails', async () => {
    getOverview.mockRejectedValue({ body: { message: 'You need the permission.' } });
    const element = await render();
    await choose(element, 'view', 'barncrm');

    expect(byId(element, 'error').textContent).toBe('You need the permission.');
  });
});
