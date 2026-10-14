import { createElement } from 'lwc';
import FindRecords from 'c/findRecords';
import listObjects from '@salesforce/apex/FindController.listObjects';
import getPage from '@salesforce/apex/FindController.getPage';
import previewQuery from '@salesforce/apex/FindController.previewQuery';
import runQuery from '@salesforce/apex/FindController.runQuery';
import exportPage from '@salesforce/apex/FindController.exportPage';
import startServerExport from '@salesforce/apex/FindController.startServerExport';
import saveQuery from '@salesforce/apex/FindController.saveQuery';
import getObjectInfo from '@salesforce/apex/QueryFieldCatalog.getObjectInfo';
import getBulkPage from '@salesforce/apex/BulkUpdateController.getPage';
import getTargets from '@salesforce/apex/BulkUpdateController.getTargets';
import deleteQuery from '@salesforce/apex/FindController.deleteQuery';
import BarnConfirmModal from 'c/barnConfirmModal';
import listChildRelationships from '@salesforce/apex/FindController.listChildRelationships';
import { EnclosingTabId, setTabIcon, setTabLabel } from 'lightning/platformWorkspaceApi';

jest.mock('@salesforce/label/c.Core_Console_TabLabel', () => ({ default: '{0}: {1}' }), {
  virtual: true
});
import saveEdits from '@salesforce/apex/FindController.saveEdits';
import * as navigation from 'lightning/navigation';
import { TextEncoder as NodeTextEncoder } from 'util';

// jsdom has no TextEncoder; the Excel writer needs one, as browsers have.
global.TextEncoder = global.TextEncoder || NodeTextEncoder;

jest.mock(
  '@salesforce/label/c.Core_Find_HiddenColumns',
  () => ({ default: 'Left out columns you do not have access to: {0}.' }),
  { virtual: true }
);
jest.mock('@salesforce/i18n/timeZone', () => ({ default: 'America/New_York' }), {
  virtual: true
});

jest.mock(
  '@salesforce/apex/FindController.listChildRelationships',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/FindController.saveEdits', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FindController.startServerExport', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FindController.summarize', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_Find_EditSaved',
  () => ({ default: 'Saved {0}. {1} unchanged.' }),
  { virtual: true }
);

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
jest.mock(
  '@salesforce/label/c.Core_Find_DeleteConfirmBody',
  () => ({ default: '{0} will be deleted.' }),
  { virtual: true }
);
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
    // Outside a console the tab is left as it is.
    expect(setTabLabel).not.toHaveBeenCalled();
  });

  it('names the console tab for the object being searched', async () => {
    const element = await render();
    EnclosingTabId.emit('tab0');
    await flush();
    expect(setTabLabel).toHaveBeenLastCalledWith('tab0', 'c.Core_Find_Title');
    expect(setTabIcon).toHaveBeenCalledWith('tab0', 'utility:search', {
      iconAlt: 'c.Core_Find_Title'
    });

    await choose(one(element, 'object'), 'Gift__c');

    expect(setTabLabel).toHaveBeenLastCalledWith('tab0', 'c.Core_Find_Title: Gift');
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

  it('keeps open the query a Save as wrote, even when another has the same name', async () => {
    const twoOfTheSameName = {
      ...PAGE,
      savedQueries: [
        { recordId: 'a0X000000000AAAAAA', name: 'Mine', mine: true, queryJson: '{}' },
        { recordId: 'a0X000000000BBBBBB', name: 'Mine', mine: true, queryJson: '{}' }
      ]
    };
    saveQuery
      .mockResolvedValueOnce({ ...twoOfTheSameName, savedId: 'a0X000000000BBBBBB' })
      .mockResolvedValueOnce({ ...twoOfTheSameName, savedId: 'a0X000000000BBBBBB' });
    const element = await render();
    await choose(one(element, 'object'), 'Gift__c');
    const name = one(element, 'query-name');
    name.value = 'Mine';
    name.dispatchEvent(new CustomEvent('change'));
    await flush();

    one(element, 'save-as').click();
    await flush();
    await flush();
    one(element, 'save').click();
    await flush();
    await flush();

    expect(saveQuery).toHaveBeenCalledTimes(2);
    expect(saveQuery.mock.calls[0][0].recordId).toBeNull();
    expect(saveQuery.mock.calls[1][0].recordId).toBe('a0X000000000BBBBBB');
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

  describe('deleting a saved query (FINDA-15)', () => {
    const MINE = { ...PAGE.savedQueries[0], mine: true, name: 'My gifts' };

    async function openOwn(shared) {
      getPage.mockResolvedValue({ ...PAGE, savedQueries: [{ ...MINE, shared }] });
      const element = await render();
      await flush();
      await choose(one(element, 'saved'), MINE.recordId);
      await flush();
      return element;
    }

    it('asks first, naming the query, and deletes only when confirmed', async () => {
      deleteQuery.mockResolvedValue({ ...PAGE, savedQueries: [] });
      BarnConfirmModal.open.mockResolvedValue(true);
      const element = await openOwn(false);

      one(element, 'delete').click();
      await flush();

      expect(BarnConfirmModal.open).toHaveBeenCalledTimes(1);
      const dialog = BarnConfirmModal.open.mock.calls[0][0];
      expect(dialog.message).toContain('My gifts');
      expect(dialog.details).toEqual([]);
      expect(dialog.confirmVariant).toBe('destructive');
      expect(deleteQuery).toHaveBeenCalledWith({ recordId: MINE.recordId });
    });

    it('says a shared query goes away for everyone', async () => {
      deleteQuery.mockResolvedValue({ ...PAGE, savedQueries: [] });
      BarnConfirmModal.open.mockResolvedValue(true);
      const element = await openOwn(true);

      one(element, 'delete').click();
      await flush();

      expect(BarnConfirmModal.open.mock.calls[0][0].details).toHaveLength(1);
    });

    it('keeps the query when the person cancels', async () => {
      BarnConfirmModal.open.mockResolvedValue(false);
      const element = await openOwn(true);

      one(element, 'delete').click();
      await flush();

      expect(deleteQuery).not.toHaveBeenCalled();
      expect(one(element, 'saved').value).toBe(MINE.recordId);
    });
  });

  describe('the SOQL preview while typing (FINDA-4)', () => {
    function holdPreviewTimers() {
      const pending = [];
      const realSetTimeout = window.setTimeout;
      jest.spyOn(window, 'setTimeout').mockImplementation((callback, delay, ...args) => {
        if (delay === 300) {
          pending.push(callback);
          return pending.length;
        }
        return realSetTimeout.call(window, callback, delay, ...args);
      });
      jest.spyOn(window, 'clearTimeout').mockImplementation((id) => {
        if (id && id <= pending.length) {
          pending[id - 1] = () => {};
        }
      });
      return pending;
    }

    function change(element, value) {
      element.shadowRoot.querySelector('c-filter-builder').dispatchEvent(
        new CustomEvent('change', {
          detail: {
            value: JSON.stringify({
              version: 1,
              conditions: [{ id: 1, field: 'Amount__c', operator: 'greater than', value }]
            }),
            valid: true
          }
        })
      );
    }

    it('asks the server once for a burst of keystrokes, after the pause', async () => {
      const element = await render();
      await choose(one(element, 'object'), 'Gift__c');
      const pending = holdPreviewTimers();
      previewQuery.mockClear();

      change(element, '1');
      change(element, '12');
      change(element, '123');
      expect(previewQuery).not.toHaveBeenCalled();

      pending.forEach((run) => run());
      await flush();

      expect(previewQuery).toHaveBeenCalledTimes(1);
      const sent = JSON.parse(previewQuery.mock.calls[0][0].queryJson);
      expect(sent.filter.conditions[0].value).toBe('123');
    });

    it('leaves a run error on screen while the person types', async () => {
      const element = await render();
      await choose(one(element, 'object'), 'Gift__c');
      runQuery.mockRejectedValue({ body: { message: 'The run failed.' } });
      one(element, 'run').click();
      await flush();
      await flush();
      expect(element.shadowRoot.textContent).toContain('The run failed.');
      const pending = holdPreviewTimers();

      change(element, '5');
      pending.forEach((run) => run());
      await flush();

      expect(element.shadowRoot.textContent).toContain('The run failed.');
    });
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

  it('offers bulk delete only with its permission, one bulk panel at a time', async () => {
    getBulkPage.mockResolvedValue({ runLimit: 48000, maxChanges: 5 });
    getTargets.mockResolvedValue([]);
    getPage.mockResolvedValue({ ...PAGE, canBulkUpdate: true });
    const element = await render();
    await choose(one(element, 'object'), 'Gift__c');
    expect(one(element, 'bulk-delete')).toBeNull();
    element.remove();

    getPage.mockResolvedValue({ ...PAGE, canBulkUpdate: true, canBulkDelete: true });
    const allowed = await render();
    await choose(one(allowed, 'object'), 'Gift__c');
    one(allowed, 'bulk-update').click();
    await flush();
    one(allowed, 'bulk-delete').click();
    await flush();

    expect(allowed.shadowRoot.querySelector('c-bulk-update')).toBeNull();
    const panel = allowed.shadowRoot.querySelector('c-bulk-delete');
    expect(panel.queryJson).toBe(
      JSON.stringify({ version: 1, object: 'Gift__c', fields: ['Name'], limit: 200 })
    );
    await choose(one(allowed, 'columns'), ['Name', 'Amount__c']);
    expect(allowed.shadowRoot.querySelector('c-bulk-delete')).toBeNull();
  });

  /* ---------- Advanced Find (C-36) ---------- */

  it('opens and runs the saved query a link names in its page state', async () => {
    runQuery.mockResolvedValue({ soql: 'SELECT ...', rows: [] });
    const element = await render();
    // Reached through the module namespace: a wire adapter may only be named in @wire.
    navigation.CurrentPageReference.emit({ state: { c__savedQueryId: 'a0X000000000001AAA' } });
    await flush();
    await flush();
    await flush();

    expect(one(element, 'saved').value).toBe('a0X000000000001AAA');
    expect(one(element, 'columns').value).toEqual(['Name', 'Donor_Contact__r.LastName']);
    expect(runQuery).toHaveBeenCalledTimes(1);
    expect(JSON.parse(runQuery.mock.calls[0][0].queryJson)).toEqual(
      expect.objectContaining({ object: 'Gift__c', limit: 50 })
    );
  });

  it('leaves out a shared column the person cannot see, and says so', async () => {
    const hidden = { ...PAGE.savedQueries[0] };
    hidden.queryJson = JSON.stringify({
      version: 1,
      object: 'Gift__c',
      fields: ['Name', 'Secret__c', 'Amount__c'],
      limit: 50
    });
    getPage.mockResolvedValue({ ...PAGE, savedQueries: [hidden] });
    const element = await render();
    await flush();
    await choose(one(element, 'saved'), hidden.recordId);
    await flush();

    expect(one(element, 'columns').value).toEqual(['Name', 'Amount__c']);
    expect(one(element, 'notice-message').textContent).toBe(
      'Left out columns you do not have access to: Secret__c.'
    );
  });

  it('shows and exports a date-time with its time, in the person time zone', async () => {
    const withTime = {
      ...GIFT,
      fields: [
        ...GIFT.fields,
        { apiName: 'Received__c', label: 'Received', dataType: 'datetime', filterable: true }
      ]
    };
    getObjectInfo.mockImplementation(({ objectApiName }) =>
      Promise.resolve(objectApiName === 'Contact' ? CONTACT : withTime)
    );
    runQuery.mockResolvedValue({
      soql: 'SELECT ...',
      rows: [{ Id: 'a01', Name: 'G-1', Received__c: '2026-01-05T03:00:00.000Z' }]
    });
    exportPage.mockResolvedValue({
      rows: [{ Id: 'a01', Name: 'G-1', Received__c: '2026-01-05T03:00:00.000Z' }],
      lastId: 'a01',
      done: true
    });
    const element = await render();
    await choose(one(element, 'object'), 'Gift__c');
    await choose(one(element, 'columns'), ['Name', 'Received__c']);
    one(element, 'run').click();
    await flush();
    await flush();

    const shown = one(element, 'results').columns[1];
    expect(shown.type).toBe('date');
    expect(shown.typeAttributes).toEqual(
      expect.objectContaining({ hour: '2-digit', minute: '2-digit', timeZone: 'America/New_York' })
    );

    one(element, 'export').click();
    await flush();
    await flush();
    const blob = global.URL.createObjectURL.mock.calls[0][0];
    const text = await new Promise((resolve) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result);
      reader.readAsText(blob);
    });
    // Ten at night on the 4th in New York, not three in the morning UTC.
    expect(text).toContain('G-1,2026-01-04 22:00:00');
  });

  it('loads a typed query into the builder', async () => {
    const element = await render();
    await choose(one(element, 'object'), 'Contact');
    const panel = element.shadowRoot.querySelector('c-find-query-text-panel');
    panel.dispatchEvent(
      new CustomEvent('apply', {
        detail: {
          document: {
            version: 1,
            object: 'Gift__c',
            fields: ['Name', 'Amount__c'],
            filter: {
              version: 1,
              conditions: [{ id: 1, field: 'Amount__c', operator: 'greater than', value: 5 }]
            },
            limit: 10
          }
        }
      })
    );
    await flush();
    await flush();

    expect(one(element, 'object').value).toBe('Gift__c');
    expect(one(element, 'columns').value).toEqual(['Name', 'Amount__c']);
    expect(one(element, 'row-limit').value).toBe(10);
    const sent = JSON.parse(previewQuery.mock.calls.pop()[0].queryJson);
    expect(sent.filter.conditions).toHaveLength(1);
  });

  it('exports the results as an Excel workbook', async () => {
    exportPage.mockResolvedValue({
      rows: [{ Id: '1', Name: 'A', Amount__c: 12.5 }],
      lastId: '1',
      done: true
    });
    const element = await render();
    await choose(one(element, 'object'), 'Gift__c');
    await choose(one(element, 'columns'), ['Name', 'Amount__c']);
    one(element, 'export-excel').click();
    await flush();
    await flush();

    expect(one(element, 'error-message')).toBeNull();
    const blob = global.URL.createObjectURL.mock.calls[0][0];
    expect(blob.type).toBe('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    expect(blob.size).toBeGreaterThan(0);
    expect(one(element, 'notice-message').textContent).toBe('Exported 1 rows.');
  });

  it('hands the query and the column labels to the export to Files', async () => {
    startServerExport.mockResolvedValue({ jobId: '707', tag: 'abc123', done: false, files: [] });
    jest.spyOn(window, 'setInterval').mockImplementation(() => 1);
    const element = await render();
    await choose(one(element, 'object'), 'Gift__c');
    await choose(one(element, 'columns'), ['Name', 'Amount__c']);
    one(element, 'export-files').click();
    await flush();

    expect(startServerExport).toHaveBeenCalledTimes(1);
    const sent = startServerExport.mock.calls[0][0];
    expect(JSON.parse(sent.queryJson).fields).toEqual(['Name', 'Amount__c']);
    expect(Object.keys(JSON.parse(sent.labelsJson))).toEqual(['Name', 'Amount__c']);
    expect(exportPage).not.toHaveBeenCalled();
  });

  it('saves grid edits as the person and marks the rows that failed', async () => {
    getPage.mockResolvedValue({ ...PAGE, canBulkUpdate: true });
    getTargets.mockResolvedValue([
      { apiName: 'Amount__c', dataType: 'currency' },
      { apiName: 'Donor_Contact__c', dataType: 'reference' }
    ]);
    runQuery.mockResolvedValue({
      soql: 'SELECT ...',
      rows: [
        { Id: 'a01', Name: 'G-1', Amount__c: 5 },
        { Id: 'a02', Name: 'G-2', Amount__c: 6 }
      ]
    });
    saveEdits.mockResolvedValue({
      saved: 1,
      unchanged: 0,
      jobId: 'a0J1',
      errors: [{ recordId: 'a02', message: 'Amount is too large.' }]
    });
    const element = await render();
    await choose(one(element, 'object'), 'Gift__c');
    await choose(one(element, 'columns'), ['Name', 'Amount__c']);
    one(element, 'run').click();
    await flush();
    await flush();

    const table = one(element, 'results');
    expect(table.columns.map((column) => Boolean(column.editable))).toEqual([false, true]);
    const drafts = [
      { Id: 'a01', Amount__c: '7' },
      { Id: 'a02', Amount__c: '9999999' }
    ];
    table.dispatchEvent(new CustomEvent('save', { detail: { draftValues: drafts } }));
    await flush();
    await flush();

    expect(saveEdits).toHaveBeenCalledWith({
      objectApiName: 'Gift__c',
      editsJson: JSON.stringify(drafts)
    });
    expect(one(element, 'results').draftValues).toEqual([drafts[1]]);
    expect(one(element, 'results').errors.rows.a02.messages).toEqual(['Amount is too large.']);
    expect(one(element, 'notice-message').textContent).toBe('Saved 1. 0 unchanged.');
  });

  it('shows a related record column as text and asks for the related records', async () => {
    listChildRelationships.mockResolvedValue([
      {
        label: 'Payments (Gift)',
        relationshipName: 'Payments__r',
        objectName: 'Payment__c',
        field: 'Gift__c',
        filterable: true
      }
    ]);
    runQuery.mockResolvedValue({
      soql: 'SELECT ...',
      rows: [
        {
          Id: 'a01',
          Name: 'G-1',
          Payments__r: {
            records: [
              { Id: 'p1', Name: 'P-1', Status__c: 'Paid' },
              { Id: 'p2', Name: 'P-2', Status__c: null }
            ]
          }
        }
      ]
    });
    const element = await render();
    await choose(one(element, 'object'), 'Gift__c');
    const children = [{ relationship: 'Payments__r', fields: ['Name', 'Status__c'], limit: 10 }];
    element.shadowRoot
      .querySelector('c-find-related-panel')
      .dispatchEvent(new CustomEvent('change', { detail: { related: [], children, valid: true } }));
    await flush();
    one(element, 'run').click();
    await flush();
    await flush();

    expect(JSON.parse(runQuery.mock.calls[0][0].queryJson).children).toEqual(children);
    const table = one(element, 'results');
    expect(table.columns[1].label).toBe('Payments (Gift)');
    expect(table.data[0].Payments__r).toBe('P-1, Paid; P-2');
  });
});
