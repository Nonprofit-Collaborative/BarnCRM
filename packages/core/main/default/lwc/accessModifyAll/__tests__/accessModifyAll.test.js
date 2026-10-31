import { createElement } from 'lwc';
import AccessModifyAll from 'c/accessModifyAll';
import getModifyAllReport from '@salesforce/apex/AccessExplorerController.getModifyAllReport';

jest.mock(
  '@salesforce/apex/AccessExplorerController.getModifyAllReport',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Core_AccessExplorer_Yes', () => ({ default: 'Yes' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_AccessExplorer_KindProfile', () => ({ default: 'Profile' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_AccessExplorer_KindSet',
  () => ({ default: 'Permission Set' }),
  {
    virtual: true
  }
);
jest.mock('@salesforce/label/c.Core_AccessModifyAll_ScopeCustom', () => ({ default: 'Custom' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_AccessModifyAll_Truncated',
  () => ({ default: 'The list is cut at {0} rows.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_AccessExplorer_Downloaded',
  () => ({ default: 'Downloaded {0} rows.' }),
  { virtual: true }
);

const REPORT = {
  truncated: false,
  dataGrants: [
    {
      id: '0PS1',
      label: 'System Administrator',
      kind: 'profile',
      modifyAllData: true,
      activePeople: 2
    },
    { id: '0PS2', label: 'Auditor', kind: 'permissionSet', viewAllData: true, inGroups: 'Finance' },
    { id: '0PS4', label: 'Developer', kind: 'permissionSet', authorApex: true }
  ],
  objects: [
    {
      objectName: 'Gift__c',
      objectLabel: 'Gift',
      scope: 'custom',
      holderId: '0PS3',
      holder: 'Gift Admin',
      kind: 'permissionSet',
      viewAll: true,
      modifyAll: true,
      inGroups: 'Finance, Admin',
      activePeople: 1
    }
  ]
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));
const byId = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

async function render() {
  const element = createElement('c-access-modify-all', { is: AccessModifyAll });
  document.body.appendChild(element);
  await flush();
  await flush();
  return element;
}

describe('c-access-modify-all', () => {
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

  it('reads once and lists data-wide holders and object holders', async () => {
    getModifyAllReport.mockResolvedValue(REPORT);
    const element = await render();

    expect(getModifyAllReport).toHaveBeenCalledTimes(1);
    const data = byId(element, 'data').data;
    expect(data[0]).toMatchObject({
      kindLabel: 'Profile',
      modifyAllDataText: 'Yes',
      viewAllDataText: 'Yes'
    });
    expect(data[1]).toMatchObject({
      modifyAllDataText: '',
      viewAllDataText: 'Yes',
      authorApexText: '',
      inGroups: 'Finance'
    });
    expect(data[2]).toMatchObject({
      authorApexText: 'Yes',
      modifyAllDataText: '',
      viewAllDataText: ''
    });
    const objects = byId(element, 'objects').data;
    expect(objects[0]).toMatchObject({
      scopeLabel: 'Custom',
      kindLabel: 'Permission Set',
      modifyAllText: 'Yes',
      viewAllText: 'Yes',
      inGroups: 'Finance, Admin'
    });
    expect(byId(element, 'truncated')).toBeNull();
  });

  it('says so when the list is cut and when nothing qualifies', async () => {
    getModifyAllReport.mockResolvedValue({ truncated: true, dataGrants: [], objects: [] });
    const element = await render();

    expect(byId(element, 'truncated').textContent).toBe('The list is cut at 2,000 rows.');
    expect(byId(element, 'data-empty')).not.toBeNull();
    expect(byId(element, 'objects-empty')).not.toBeNull();
  });

  it('shows what went wrong', async () => {
    getModifyAllReport.mockRejectedValue({ body: { message: 'No permission.' } });
    const element = await render();

    expect(byId(element, 'error').textContent).toContain('No permission.');
    expect(byId(element, 'data')).toBeNull();
  });

  it('downloads the table asked for', async () => {
    getModifyAllReport.mockResolvedValue(REPORT);
    const element = await render();

    element.shadowRoot.querySelector('lightning-button[data-table="objects"]').click();
    await flush();

    const text = await new Promise((resolve) => {
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result));
      reader.readAsText(csv);
    });
    expect(text).toContain('Gift Admin');
    expect(text).not.toContain('System Administrator');
    expect(byId(element, 'notice').textContent).toBe('Downloaded 1 rows.');
  });
});
