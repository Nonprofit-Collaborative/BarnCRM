import { createElement } from 'lwc';
import BarnConfirmModal from 'c/barnConfirmModal';
import FieldAccessManager from 'c/fieldAccessManager';
import getStatus from '@salesforce/apex/FieldAccessController.getStatus';
import searchSets from '@salesforce/apex/FieldAccessController.searchSets';
import getFields from '@salesforce/apex/FieldAccessController.getFields';
import previewChange from '@salesforce/apex/FieldAccessController.preview';
import applyChange from '@salesforce/apex/FieldAccessController.apply';
import undoChange from '@salesforce/apex/FieldAccessController.undo';
import listChanges from '@salesforce/apex/FieldAccessController.listChanges';
import listObjects from '@salesforce/apex/DataDictionaryController.listObjects';
import { setHelpTextForTest } from 'c/barnHelpText';

setHelpTextForTest({
  Core_FieldAccess_PreviewSummary: '{0} rows change on {1} permission sets; {2} are already right.',
  Core_FieldAccess_Applied: 'Changed {0} rows; {1} refused.',
  Core_FieldAccess_Conflict: '{0} is set to No Access.'
});

jest.mock('@salesforce/apex/FieldAccessController.getStatus', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FieldAccessController.searchSets', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FieldAccessController.getFields', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FieldAccessController.preview', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FieldAccessController.apply', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FieldAccessController.undo', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FieldAccessController.listChanges', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/DataDictionaryController.listObjects',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_FieldAccess_NowText',
  () => ({ default: 'Read: {0} of {2}. Edit: {1} of {2}.' }),
  { virtual: true }
);

const STATUS = { canChange: true, maxSets: 10, maxItems: 500, maxRows: 2000 };
const FIELDS = {
  objectName: 'Contact',
  objectLabel: 'Contact',
  setCount: 1,
  objectAccess: [{ setId: '0PS1', setLabel: 'Event Volunteers', read: false, edit: false }],
  fields: [
    { name: 'Email', label: 'Email', readOnly: false, readCount: 0, editCount: 0 },
    { name: 'Age__c', label: 'Age', readOnly: true, readCount: 1, editCount: 0 }
  ]
};
const PREVIEW = {
  changed: 2,
  unchanged: 0,
  setCount: 1,
  maxRows: 2000,
  tooMany: false,
  rows: [
    {
      setId: '0PS1',
      setLabel: 'Event Volunteers',
      objectName: 'Contact',
      objectLabel: 'Contact',
      fieldName: null,
      nowRead: false,
      nowEdit: false,
      afterRead: true,
      afterEdit: false,
      reason: 'neededForFields'
    },
    {
      setId: '0PS1',
      setLabel: 'Event Volunteers',
      objectName: 'Contact',
      objectLabel: 'Contact',
      fieldName: 'Email',
      fieldLabel: 'Email',
      nowRead: false,
      nowEdit: false,
      afterRead: true,
      afterEdit: true,
      reason: 'asked'
    }
  ]
};

const flush = () => Promise.resolve();
const settle = async () => {
  for (let i = 0; i < 5; i++) {
    // eslint-disable-next-line no-await-in-loop
    await flush();
  }
};
const byId = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

async function render() {
  const element = createElement('c-field-access-manager', { is: FieldAccessManager });
  document.body.appendChild(element);
  listObjects.emit([{ value: 'Contact', label: 'Contact', isDefault: true }]);
  await settle();
  return element;
}

async function chooseSet(element) {
  const search = byId(element, 'set-search');
  search.value = 'Ev';
  search.dispatchEvent(new CustomEvent('change'));
  // The search waits for a pause in typing.
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  await new Promise((resolve) => setTimeout(resolve, 350));
  await settle();
  byId(element, 'set-results').querySelector('lightning-button').click();
  await settle();
}

async function choose(element, id, value) {
  byId(element, id).dispatchEvent(new CustomEvent('change', { detail: { value } }));
  await settle();
}

describe('c-field-access-manager', () => {
  beforeEach(() => {
    getStatus.mockResolvedValue(STATUS);
    listChanges.mockResolvedValue([]);
    searchSets.mockResolvedValue([{ id: '0PS1', label: 'Event Volunteers' }]);
    getFields.mockResolvedValue(FIELDS);
    previewChange.mockResolvedValue(PREVIEW);
    applyChange.mockResolvedValue({ changed: 2, refused: 0, kept: 0, failures: [] });
    BarnConfirmModal.open.mockResolvedValue(true);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('says why and offers nothing without the permissions', async () => {
    getStatus.mockResolvedValue({ canChange: false, reason: 'You need Manage Profiles.' });
    const element = await render();
    expect(byId(element, 'refusal').message).toBe('You need Manage Profiles.');
    expect(byId(element, 'set-search')).toBeNull();
    expect(listChanges).not.toHaveBeenCalled();
  });

  it('chooses a set, adds fields, previews, applies and lists the change', async () => {
    const element = await render();
    expect(byId(element, 'preview').disabled).toBe(true);
    expect(byId(element, 'object').disabled).toBe(true);

    await chooseSet(element);
    expect(searchSets).toHaveBeenCalledWith({ term: 'Ev' });
    expect(byId(element, 'chosen-sets').querySelectorAll('lightning-pill')).toHaveLength(1);

    await choose(element, 'object', 'Contact');
    expect(getFields).toHaveBeenCalledWith({ objectName: 'Contact', setIds: ['0PS1'] });
    const table = byId(element, 'fields');
    expect(table.data.map((row) => row.nowText)).toEqual([
      'Read: 0 of 1. Edit: 0 of 1.',
      'Read: 1 of 1. Edit: 0 of 1.'
    ]);
    expect(table.data[1].noteText).toBe('c.Core_FieldAccess_ReadOnlyNote');

    table.dispatchEvent(
      new CustomEvent('rowselection', {
        detail: { selectedRows: [{ name: 'Email' }, { name: 'Age__c' }] }
      })
    );
    await settle();
    byId(element, 'add').click();
    await settle();
    const items = byId(element, 'items').data;
    expect(items.map((item) => [item.fieldText, item.accessText])).toEqual([
      ['Email', 'c.Core_FieldAccess_ReadEdit'],
      ['Age', 'c.Core_AccessExplorer_ColRead']
    ]);

    byId(element, 'preview').click();
    await settle();
    expect(JSON.parse(previewChange.mock.calls[0][0].changeJson)).toEqual({
      version: 1,
      setIds: ['0PS1'],
      items: [
        { object: 'Contact', field: 'Contact.Email', access: 'edit' },
        { object: 'Contact', field: 'Contact.Age__c', access: 'read' }
      ]
    });
    expect(byId(element, 'summary').textContent).toBe(
      '2 rows change on 1 permission sets; 0 are already right.'
    );
    const rows = byId(element, 'preview-rows').data;
    expect(rows[0].fieldText).toBe('c.Core_FieldAccess_WholeRecord');
    expect(rows[0].whyText).toBe('c.Core_FieldAccess_WhyNeeded');

    listChanges.mockResolvedValue([
      {
        id: 'a01',
        createdAt: '2026-11-02T10:00:00.000Z',
        byName: 'Maria',
        changed: 2,
        refused: 0,
        status: 'Complete',
        canUndo: true,
        undoDeadline: '2026-12-02T10:00:00.000Z'
      }
    ]);
    jest.useFakeTimers();
    byId(element, 'apply').click();
    await settle();
    expect(BarnConfirmModal.open).toHaveBeenCalledTimes(1);
    expect(applyChange).toHaveBeenCalledWith({
      changeJson: previewChange.mock.calls[0][0].changeJson,
      confirmedCount: 2
    });
    expect(byId(element, 'notice').message).toBe('Changed 2 rows; 0 refused.');
    expect(byId(element, 'no-changes')).not.toBeNull();
    jest.runOnlyPendingTimers();
    jest.useRealTimers();
    await settle();
    expect(byId(element, 'recent').data[0].undoDisabled).toBe(false);
  });

  it('undoes a change after confirming', async () => {
    listChanges.mockResolvedValue([
      { id: 'a01', changed: 2, refused: 0, status: 'Complete', canUndo: true }
    ]);
    undoChange.mockResolvedValue({ changed: 2, refused: 0, kept: 1, failures: [] });
    const element = await render();
    byId(element, 'recent').dispatchEvent(
      new CustomEvent('rowaction', { detail: { row: { id: 'a01', canUndo: true } } })
    );
    await settle();
    expect(undoChange).toHaveBeenCalledWith({ jobId: 'a01' });
    expect(byId(element, 'notice').message).toBe('c.Core_FieldAccess_Undone');
  });

  it('does not apply when the confirmation is cancelled', async () => {
    BarnConfirmModal.open.mockResolvedValue(false);
    const element = await render();
    await chooseSet(element);
    await choose(element, 'object', 'Contact');
    await choose(element, 'object-access', 'read');
    byId(element, 'add').click();
    await settle();
    byId(element, 'preview').click();
    await settle();
    byId(element, 'apply').click();
    await settle();
    expect(applyChange).not.toHaveBeenCalled();
  });

  it('flags a kind of record set to No Access with fields given access', async () => {
    const element = await render();
    await chooseSet(element);
    await choose(element, 'object', 'Contact');
    await choose(element, 'object-access', 'none');
    byId(element, 'add').click();
    await settle();
    byId(element, 'fields').dispatchEvent(
      new CustomEvent('rowselection', { detail: { selectedRows: [{ name: 'Email' }] } })
    );
    await settle();
    byId(element, 'add').click();
    await settle();
    expect(byId(element, 'conflict').message).toBe('Contact is set to No Access.');
    expect(byId(element, 'preview').disabled).toBe(true);
    byId(element, 'items').dispatchEvent(
      new CustomEvent('rowaction', { detail: { row: { key: 'Contact.' } } })
    );
    await settle();
    expect(byId(element, 'conflict')).toBeNull();
  });
});
