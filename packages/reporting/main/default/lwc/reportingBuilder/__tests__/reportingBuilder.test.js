import { createElement } from 'lwc';
import ReportingBuilder from 'c/reportingBuilder';
import BarnConfirmModal from 'c/barnConfirmModal';
import listChildren from '@salesforce/apex/ReportingQueryService.listChildren';
import load from '@salesforce/apex/ReportingLibrary.load';
import save from '@salesforce/apex/ReportingLibrary.save';
import share from '@salesforce/apex/ReportingLibrary.share';
import remove from '@salesforce/apex/ReportingLibrary.remove';
import { expectAccessible } from 'barn/a11y';

jest.mock('@salesforce/apex/ReportingQueryService.listChildren', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/ReportingQueryService.run',
  () => ({ default: jest.fn(() => Promise.resolve({ rows: [] })) }),
  {
    virtual: true
  }
);
jest.mock('@salesforce/apex/ReportingQueryService.page', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/QueryFieldCatalog.getObjectInfo',
  () => ({ default: jest.fn(() => Promise.resolve({ label: 'X', fields: [] })) }),
  {
    virtual: true
  }
);
jest.mock('@salesforce/apex/ReportingLibrary.load', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ReportingLibrary.save', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ReportingLibrary.share', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ReportingLibrary.remove', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ReportingLibrary.findPeople', () => ({ default: jest.fn() }), {
  virtual: true
});

const OBJECTS = [
  { value: 'Contact', label: 'Contact' },
  { value: 'Gift__c', label: 'Gift' }
];
const CHILDREN = [
  { object: 'Gift__c', objectLabel: 'Gifts', field: 'Donor_Contact__c', fieldLabel: 'Donor' },
  {
    object: 'Volunteer_Hours__c',
    objectLabel: 'Volunteer Hours',
    field: 'Contact__c',
    fieldLabel: 'Contact'
  }
];
const SAVED_ROW = {
  id: '069000000000001AAA',
  kind: 'barnreport',
  title: 'Donors',
  ownerName: 'Ana',
  mine: true,
  canEdit: true,
  definition: JSON.stringify({
    object: 'Contact',
    columns: [{ path: 'Name', label: 'Name' }]
  }),
  sharing: { users: [{ id: '005000000000002AAA', name: 'Ben', access: 'view' }], groups: [] }
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function mount(props) {
  const element = createElement('c-reporting-builder', { is: ReportingBuilder });
  Object.assign(element, { context: { canSave: true, canExport: true }, objects: OBJECTS }, props);
  document.body.appendChild(element);
  await flush();
  await flush();
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);
const findAll = (element, id) => [...element.shadowRoot.querySelectorAll(`[data-id="${id}"]`)];
const change = (target, detail) => target.dispatchEvent(new CustomEvent('change', { detail }));

describe('c-reporting-builder', () => {
  beforeEach(() => {
    listChildren.mockResolvedValue(CHILDREN);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('builds a list report with columns, a related condition and a related total, and saves it', async () => {
    save.mockResolvedValue({ ...SAVED_ROW, title: 'Lapsed' });
    const element = await mount({});
    const saved = jest.fn();
    element.addEventListener('saved', saved);
    expect(find(element, 'run-first')).not.toBeNull();
    expect(find(element, 'run').disabled).toBe(true);

    change(find(element, 'object'), { value: 'Contact' });
    await flush();
    expect(listChildren).toHaveBeenCalledWith({ objectName: 'Contact' });
    const addColumn = find(element, 'add-column');
    addColumn.clear = jest.fn();
    change(addColumn, { path: 'Name', label: 'Name', type: 'string' });
    change(addColumn, { path: 'Name', label: 'Name', type: 'string' });
    change(addColumn, { path: 'Email', label: 'Email', type: 'email' });
    await flush();
    expect(findAll(element, 'column-remove')).toHaveLength(2);
    expect(addColumn.clear).toHaveBeenCalledTimes(3);

    find(element, 'add-related').click();
    await flush();
    expect(findAll(element, 'related-entry')).toHaveLength(1);
    find(element, 'add-summary').click();
    await flush();
    expect(findAll(element, 'summary')).toHaveLength(1);

    change(find(element, 'title'), { value: 'Lapsed' });
    await flush();
    find(element, 'run').click();
    await flush();
    const preview = find(element, 'preview');
    expect(preview.report.columns.map((column) => column.path)).toEqual(['Name', 'Email']);
    expect(preview.report.related[0]).toEqual({
      object: 'Gift__c',
      field: 'Donor_Contact__c',
      label: 'Gifts',
      has: true
    });
    expect(preview.canExport).toBe(true);
    await expectAccessible(element);

    find(element, 'save').click();
    await flush();
    const call = save.mock.calls[0][0];
    expect(call.kind).toBe('barnreport');
    expect(call.documentId).toBeNull();
    expect(JSON.parse(call.definitionJson).summaries[0].fn).toBe('count');
    expect(find(element, 'notice').message).toBe('c.Reporting_Saved');
    expect(saved).toHaveBeenCalled();
  });

  it('turns a list into totals when a grouping is added, and back when the last total goes', async () => {
    const element = await mount({ start: { object: 'Gift__c' } });
    const addGroup = find(element, 'add-group');
    addGroup.clear = jest.fn();
    change(addGroup, { path: 'Gift_Date__c', label: 'Gift Date', type: 'date' });
    await flush();
    expect(find(element, 'columns')).toBeNull();
    expect(findAll(element, 'group')).toHaveLength(1);
    expect(find(element, 'view').value).toBe('bar');
    expect(find(element, 'view').options.map((option) => option.value)).toContain('donut');

    find(element, 'add-measure').click();
    await flush();
    expect(findAll(element, 'measure')).toHaveLength(2);
    change(find(element, 'sort-by'), { value: 'm0' });
    change(find(element, 'direction'), { value: 'desc' });
    change(find(element, 'limit'), { value: '5' });
    await flush();
    expect(find(element, 'sort-by').value).toBe('m0');
    expect(find(element, 'direction').value).toBe('desc');

    const removeButtons = () =>
      findAll(element, 'measure').map((box) => box.querySelector('lightning-button-icon'));
    removeButtons()[0].click();
    await flush();
    removeButtons()[0].click();
    await flush();
    expect(findAll(element, 'group')).toHaveLength(0);
    expect(find(element, 'view').value).toBe('table');
  });

  it('opens a saved report, saves without sharing, shares and deletes', async () => {
    load.mockResolvedValue(SAVED_ROW);
    save.mockResolvedValue(SAVED_ROW);
    share.mockResolvedValue(SAVED_ROW);
    remove.mockResolvedValue();
    BarnConfirmModal.open = jest.fn(() => Promise.resolve(true));
    const element = await mount({ documentId: '069000000000001AAA' });
    const closed = jest.fn();
    element.addEventListener('close', closed);
    expect(find(element, 'heading').textContent).toBe('Donors');
    expect(find(element, 'preview')).not.toBeNull();

    find(element, 'save').click();
    await flush();
    const definition = JSON.parse(save.mock.calls[0][0].definitionJson);
    expect(save.mock.calls[0][0].documentId).toBe('069000000000001AAA');
    // Sharing never goes with a save, so a stale save cannot change who has access.
    expect(definition.sharing).toBeUndefined();

    find(element, 'share').click();
    await flush();
    const panel = find(element, 'share-panel');
    expect(panel.sharing.users[0].id).toBe('005000000000002AAA');
    panel.dispatchEvent(
      new CustomEvent('save', { detail: { sharing: { users: [], groups: [] } } })
    );
    await flush();
    expect(JSON.parse(share.mock.calls[0][0].sharingJson)).toEqual({ users: [], groups: [] });
    expect(find(element, 'share-panel')).toBeNull();

    find(element, 'delete').click();
    await flush();
    expect(remove).toHaveBeenCalledWith({ documentId: '069000000000001AAA' });
    expect(closed).toHaveBeenCalled();
  });

  it('opens a report shared to view as read only, with Save As only', async () => {
    load.mockResolvedValue({ ...SAVED_ROW, mine: false, canEdit: false });
    const element = await mount({ documentId: '069000000000001AAA' });
    expect(find(element, 'read-only')).not.toBeNull();
    expect(find(element, 'owner').textContent).toBe('c.Reporting_Builder_Owner');
    expect(find(element, 'save')).toBeNull();
    expect(find(element, 'share')).toBeNull();
    expect(find(element, 'save-as')).not.toBeNull();
  });

  it('asks for a name before saving and shows a refused save', async () => {
    save.mockRejectedValue({ body: { message: 'Saving needs a permission set.' } });
    const element = await mount({ start: { object: 'Contact', columns: [{ path: 'Name' }] } });
    find(element, 'save').click();
    await flush();
    expect(find(element, 'error').message).toBe('c.Reporting_Error_Title');
    change(find(element, 'title'), { value: 'Named' });
    await flush();
    find(element, 'save-as').click();
    await flush();
    expect(find(element, 'error').message).toBe('Saving needs a permission set.');
  });

  it('edits a widget report and hands it back with Done', async () => {
    const element = await mount({
      forWidget: true,
      start: { object: 'Contact', columns: [{ path: 'Name' }] }
    });
    const done = jest.fn();
    element.addEventListener('done', done);
    expect(find(element, 'save')).toBeNull();
    find(element, 'done').click();
    expect(done.mock.calls[0][0].detail.report.object).toBe('Contact');
  });
});
