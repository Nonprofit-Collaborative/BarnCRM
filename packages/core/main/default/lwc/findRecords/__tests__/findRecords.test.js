import { createElement } from 'lwc';
import FindRecords from 'c/findRecords';
import listObjects from '@salesforce/apex/FindController.listObjects';
import getPage from '@salesforce/apex/FindController.getPage';
import previewQuery from '@salesforce/apex/FindController.previewQuery';
import runQuery from '@salesforce/apex/FindController.runQuery';
import exportPage from '@salesforce/apex/FindController.exportPage';
import saveQuery from '@salesforce/apex/FindController.saveQuery';
import getObjectInfo from '@salesforce/apex/QueryFieldCatalog.getObjectInfo';
import getBulkPage from '@salesforce/apex/BulkUpdateController.getPage';
import getTargets from '@salesforce/apex/BulkUpdateController.getTargets';

jest.mock(
  '@salesforce/apex/FindController.listObjects',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock('@salesforce/apex/FindController.getPage', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FindController.previewQuery', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FindController.runQuery', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FindController.exportPage', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FindController.saveQuery', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FindController.deleteQuery', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkUpdateController.getPage', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkUpdateController.getTargets', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/QueryFieldCatalog.getObjectInfo', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_Find_ExportDone', () => ({ default: 'Exported {0} rows.' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_Find_ExportStopped',
  () => ({ default: 'Stopped at {0} rows.' }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Core_Find_ResultCount', () => ({ default: '{0} rows shown.' }), {
  virtual: true
});

const GIFT = {
  apiName: 'Gift__c',
  label: 'Gift',
  fields: [
    { apiName: 'Name', label: 'Gift Name', dataType: 'string', filterable: true, sortable: true },
    {
      apiName: 'Amount__c',
      label: 'Amount',
      dataType: 'currency',
      filterable: true,
      sortable: true
    },
    {
      apiName: 'Donor_Contact__c',
      label: 'Donor',
      dataType: 'reference',
      filterable: true,
      sortable: true,
      referenceTo: 'Contact',
      relationshipName: 'Donor_Contact__r'
    }
  ]
};
const CONTACT = {
  apiName: 'Contact',
  label: 'Contact',
  fields: [{ apiName: 'LastName', label: 'Last Name', dataType: 'string', filterable: true }]
};
const PAGE = {
  exportLimit: 3,
  maxRows: 2000,
  exportPageSize: 2000,
  savedQueries: [
    {
      recordId: 'a0X000000000001AAA',
      name: 'Big gifts',
      objectName: 'Gift__c',
      mine: false,
      ownerName: 'Priya',
      shared: true,
      queryJson: JSON.stringify({
        version: 1,
        object: 'Gift__c',
        fields: ['Name', 'Donor_Contact__r.LastName'],
        filter: {
          version: 1,
          conditions: [{ id: 1, field: 'Amount__c', operator: 'greater than', value: 1000 }]
        },
        orderBy: [{ field: 'Amount__c', direction: 'DESC' }],
        limit: 50
      })
    }
  ]
};

// A macrotask, because the page awaits describes and Apex calls in a row.
// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));
const one = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

async function render() {
  const element = createElement('c-find-records', { is: FindRecords });
  document.body.appendChild(element);
  listObjects.emit([
    { label: 'Contact', value: 'Contact' },
    { label: 'Gift', value: 'Gift__c' }
  ]);
  await flush();
  return element;
}

async function choose(target, value) {
  target.dispatchEvent(new CustomEvent('change', { detail: { value } }));
  await flush();
  await flush();
}

describe('c-find-records', () => {
  beforeEach(() => {
    getPage.mockResolvedValue(PAGE);
    previewQuery.mockResolvedValue('SELECT Id, Name FROM Gift__c LIMIT 200');
    getObjectInfo.mockImplementation(({ objectApiName }) => {
      return Promise.resolve(objectApiName === 'Contact' ? CONTACT : GIFT);
    });
    global.URL.createObjectURL = jest.fn(() => 'blob:csv');
    global.URL.revokeObjectURL = jest.fn();
    // jsdom cannot follow a download link; the click is what matters here.
    jest.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    jest.restoreAllMocks();
  });

  it('offers the objects and starts a query with the name column and its SOQL', async () => {
    const element = await render();
    expect(one(element, 'object').options).toHaveLength(2);

    await choose(one(element, 'object'), 'Gift__c');

    expect(one(element, 'columns').value).toEqual(['Name']);
    expect(previewQuery).toHaveBeenCalledWith({
      queryJson: JSON.stringify({ version: 1, object: 'Gift__c', fields: ['Name'], limit: 200 })
    });
    expect(one(element, 'soql').value).toBe('SELECT Id, Name FROM Gift__c LIMIT 200');
    expect(element.shadowRoot.querySelector('c-filter-builder').objectApiName).toBe('Gift__c');
  });

  it('adds a related record so its fields can be columns, and shows them in the results', async () => {
    runQuery.mockResolvedValue({
      soql: 'SELECT ...',
      rows: [{ Id: 'a01', Name: 'G-1', Donor_Contact__r: { LastName: 'Garcia' } }]
    });
    const element = await render();
    await choose(one(element, 'object'), 'Gift__c');
    await choose(one(element, 'related'), 'Donor_Contact__r');

    const values = one(element, 'columns').options.map((option) => option.value);
    expect(values).toContain('Donor_Contact__r.LastName');
    expect(
      one(element, 'columns').options.find((o) => o.value === 'Donor_Contact__r.LastName').label
    ).toBe('Donor > Last Name');

    await choose(one(element, 'columns'), ['Name', 'Donor_Contact__r.LastName']);
    one(element, 'run').click();
    await flush();
    await flush();

    const table = one(element, 'results');
    expect(table.data).toEqual([{ Id: 'a01', Name: 'G-1', 'Donor_Contact__r.LastName': 'Garcia' }]);
    expect(table.columns[1].label).toBe('Donor > Last Name');
    expect(one(element, 'result-line').textContent.trim()).toBe('1 rows shown.');
  });

  it('refuses to run with no columns and says why', async () => {
    const element = await render();
    await choose(one(element, 'object'), 'Gift__c');
    await choose(one(element, 'columns'), []);
    one(element, 'run').click();
    await flush();
    expect(runQuery).not.toHaveBeenCalled();
    expect(one(element, 'error-message').textContent).toBe('c.Core_Find_ChooseColumns');
  });

  it('exports page by page and stops at the export limit', async () => {
    exportPage
      .mockResolvedValueOnce({
        rows: [
          { Id: '1', Name: 'A' },
          { Id: '2', Name: 'B' }
        ],
        lastId: '2',
        done: false
      })
      .mockResolvedValueOnce({
        rows: [
          { Id: '3', Name: 'C' },
          { Id: '4', Name: 'D' }
        ],
        lastId: '4',
        done: false
      });
    const element = await render();
    await choose(one(element, 'object'), 'Gift__c');
    one(element, 'export').click();
    await flush();
    await flush();

    expect(exportPage).toHaveBeenCalledTimes(2);
    expect(exportPage.mock.calls[1][0].afterId).toBe('2');
    expect(global.URL.createObjectURL).toHaveBeenCalled();
    expect(one(element, 'notice-message').textContent).toBe('Stopped at 3 rows.');
  });

  it('saves a new query with its name and sharing', async () => {
    saveQuery.mockResolvedValue({
      ...PAGE,
      savedQueries: [{ recordId: 'a0X2', name: 'Mine', mine: true, queryJson: '{}' }]
    });
    const element = await render();
    await choose(one(element, 'object'), 'Gift__c');
    const name = one(element, 'query-name');
    name.value = 'Mine';
    name.dispatchEvent(new CustomEvent('change'));
    const share = one(element, 'share');
    share.checked = true;
    share.dispatchEvent(new CustomEvent('change'));
    await flush();

    one(element, 'save').click();
    await flush();
    await flush();

    expect(saveQuery).toHaveBeenCalledWith(
      expect.objectContaining({ recordId: null, name: 'Mine', shared: true })
    );
    expect(one(element, 'notice-message').textContent).toBe('c.Core_Find_SavedNotice');
  });

  it('opens a query someone shared, read only, with its related columns and conditions', async () => {
    const element = await render();
    await flush();
    await choose(one(element, 'saved'), 'a0X000000000001AAA');
    await flush();

    expect(one(element, 'columns').value).toEqual(['Name', 'Donor_Contact__r.LastName']);
    expect(one(element, 'sort').value).toBe('Amount__c');
    expect(one(element, 'direction').value).toBe('DESC');
    expect(one(element, 'row-limit').value).toBe(50);
    expect(
      JSON.parse(element.shadowRoot.querySelector('c-filter-builder').value).conditions[0].field
    ).toBe('Amount__c');
    expect(one(element, 'save').disabled).toBe(true);
    expect(one(element, 'save-as').disabled).toBe(false);
  });

  it('shows the refusal when Find cannot load', async () => {
    getPage.mockRejectedValue({
      body: { message: 'Find needs the Find and Export Records permission.' }
    });
    const element = await render();
    await flush();
    expect(one(element, 'error-message').textContent).toBe(
      'Find needs the Find and Export Records permission.'
    );
  });

  it('offers bulk update only with the permission, over the query as it is', async () => {
    getBulkPage.mockResolvedValue({ runLimit: 48000, maxChanges: 5 });
    getTargets.mockResolvedValue([]);
    const element = await render();
    await choose(one(element, 'object'), 'Gift__c');
    expect(one(element, 'bulk-update')).toBeNull();
    element.remove();

    getPage.mockResolvedValue({ ...PAGE, canBulkUpdate: true });
    const allowed = await render();
    await choose(one(allowed, 'object'), 'Gift__c');
    one(allowed, 'bulk-update').click();
    await flush();

    const panel = allowed.shadowRoot.querySelector('c-bulk-update');
    expect(panel.queryJson).toBe(
      JSON.stringify({ version: 1, object: 'Gift__c', fields: ['Name'], limit: 200 })
    );
    panel.dispatchEvent(new CustomEvent('close'));
    await flush();
    expect(allowed.shadowRoot.querySelector('c-bulk-update')).toBeNull();
  });

  it('closes the bulk update panel when the query changes', async () => {
    getBulkPage.mockResolvedValue({ runLimit: 48000, maxChanges: 5 });
    getTargets.mockResolvedValue([]);
    getPage.mockResolvedValue({ ...PAGE, canBulkUpdate: true });
    const element = await render();
    await choose(one(element, 'object'), 'Gift__c');
    one(element, 'bulk-update').click();
    await flush();
    expect(element.shadowRoot.querySelector('c-bulk-update')).not.toBeNull();

    await choose(one(element, 'columns'), ['Name', 'Amount__c']);

    expect(element.shadowRoot.querySelector('c-bulk-update')).toBeNull();
  });
});
