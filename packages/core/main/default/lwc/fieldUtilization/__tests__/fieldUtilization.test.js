import { createElement } from 'lwc';
import FieldUtilization from 'c/fieldUtilization';
import WhereUsedModal from 'c/whereUsedModal';
import listObjects from '@salesforce/apex/FieldUtilizationController.listObjects';
import getPlan from '@salesforce/apex/FieldUtilizationController.getPlan';
import countFields from '@salesforce/apex/FieldUtilizationController.countFields';
import saveCounts from '@salesforce/apex/FieldUtilizationController.saveCounts';
import getHistory from '@salesforce/apex/FieldUtilizationController.getHistory';
import getSnapshotRows from '@salesforce/apex/FieldUtilizationController.getSnapshotRows';
import deleteSnapshot from '@salesforce/apex/FieldUtilizationController.deleteSnapshot';
import BarnConfirmModal from 'c/barnConfirmModal';
import { setHelpTextForTest } from 'c/barnHelpText';

setHelpTextForTest({
  Core_FieldUtilization_HistoryLimit: 'Showing the newest {0} snapshots.',
  Core_FieldUtilization_DeleteConfirm: 'Deletes the {1} counts taken on {0}.',
  Core_FieldUtilization_Progress: 'Counted {0} of {1} fields.',
  Core_FieldUtilization_Saved: 'Saved {0} counts.',
  Core_FieldUtilization_TooLarge: 'More than {0} records.',
  Core_FieldUtilization_NotCounted: 'Not counted: {0}'
});

setHelpTextForTest({
  Core_FieldUtilization_SaveHelp: 'Keeps this count so your next count shows what changed.'
});

jest.mock(
  '@salesforce/apex/FieldUtilizationController.getHistory',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/FieldUtilizationController.getSnapshotRows',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/FieldUtilizationController.deleteSnapshot',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/FieldUtilizationController.listObjects',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock('@salesforce/apex/FieldUtilizationController.getPlan', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/FieldUtilizationController.countFields',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/FieldUtilizationController.saveCounts',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Core_FieldUtilization_Save', () => ({ default: 'Save Snapshot' }), {
  virtual: true
});

const OPTIONS = [
  { value: 'Account', label: 'Account' },
  { value: 'Contact', label: 'Contact' }
];

const field = (name) => ({ fieldName: name, fieldLabel: name });

const row = (name, filled, percent) => ({
  key: `${name}|Organization`,
  fieldName: name,
  fieldLabel: name,
  recordType: 'Organization',
  recordTypeLabel: 'Organization',
  filled,
  total: 100,
  percent,
  sampled: false
});

const PLAN = {
  objectName: 'Account',
  objectLabel: 'Account',
  total: 100,
  tooLarge: false,
  largeObjectLimit: 1000000,
  chunkSize: 2,
  fields: [field('Phone'), field('Website'), field('Fax')],
  previousTakenAt: '2026-10-04T08:00:00.000Z',
  previous: [row('Phone', 75, 75.0)]
};

const flush = async () => {
  for (let i = 0; i < 8; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

function render() {
  const element = createElement('c-field-utilization', { is: FieldUtilization });
  document.body.appendChild(element);
  listObjects.emit(OPTIONS);
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

async function choose(element, value) {
  find(element, 'object').dispatchEvent(new CustomEvent('change', { detail: { value } }));
  await flush();
}

describe('c-field-utilization', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('offers the objects the controller lists and counts nothing until one is chosen', async () => {
    const element = render();
    await flush();

    expect(find(element, 'object').options).toEqual(OPTIONS);
    expect(getPlan).not.toHaveBeenCalled();
    expect(find(element, 'save').disabled).toBe(true);
    expect(find(element, 'results')).toBeNull();
  });

  it('names the save button Save Snapshot and explains it in small text', async () => {
    const element = render();
    await flush();

    expect(find(element, 'save').label).toBe('Save Snapshot');
    const help = find(element, 'save-help');
    expect(help.textContent).toBe('Keeps this count so your next count shows what changed.');
    expect(help.classList.contains('slds-text-body_small')).toBe(true);
  });

  it('counts the fields in chunks and fills the table with the change since the saved count', async () => {
    getPlan.mockResolvedValue(PLAN);
    countFields
      .mockResolvedValueOnce({
        rows: [row('Phone', 80, 80.0), row('Website', 10, 10.0)],
        failed: []
      })
      .mockResolvedValueOnce({ rows: [], failed: ['Fax'] });
    const element = render();
    await choose(element, 'Account');

    expect(getPlan).toHaveBeenCalledWith({ objectName: 'Account' });
    expect(countFields).toHaveBeenNthCalledWith(1, {
      objectName: 'Account',
      fieldNames: ['Phone', 'Website']
    });
    expect(countFields).toHaveBeenNthCalledWith(2, { objectName: 'Account', fieldNames: ['Fax'] });
    const rows = find(element, 'results').data;
    expect(rows).toHaveLength(2);
    expect(rows[0].share).toBeCloseTo(0.8);
    expect(rows[0].previousShare).toBeCloseTo(0.75);
    expect(rows[0].change).toBe(5);
    expect(rows[1].change).toBeNull();
    expect(element.shadowRoot.textContent).toContain('Counted 3 of 3 fields.');
    expect(find(element, 'not-counted').message).toContain('Not counted: Fax');
    expect(find(element, 'compared')).not.toBeNull();
    expect(find(element, 'save').disabled).toBe(false);

    // admin-24: the API Name column shows only with Show technical names on.
    const fieldNames = () => find(element, 'results').columns.map((c) => c.fieldName);
    expect(fieldNames()).not.toContain('fieldName');
    const toggle = find(element, 'technical-names');
    toggle.checked = true;
    toggle.dispatchEvent(new CustomEvent('change'));
    await flush();
    expect(fieldNames()[1]).toBe('fieldName');
  });

  it('shows Required, Default Value and At Default for each counted field (R-FU13, R-FU14)', async () => {
    getPlan.mockResolvedValue({ ...PLAN, chunkSize: 40 });
    countFields.mockResolvedValue({
      rows: [
        { ...row('Phone', 80, 80.0), required: true },
        {
          ...row('Website', 10, 10.0),
          defaultValue: 'Draft',
          atDefault: 40,
          atDefaultPercent: 40.0
        },
        { ...row('Fax', 100, 100.0), defaultFormula: 'TODAY() + 7' }
      ],
      failed: []
    });
    const element = render();
    await choose(element, 'Account');

    const table = find(element, 'results');
    const names = table.columns.map((c) => c.fieldName);
    expect(names).toEqual(expect.arrayContaining(['required', 'defaultShown', 'atDefaultShare']));
    expect(names.indexOf('atDefaultShare')).toBe(names.indexOf('total') + 1);
    expect(table.columns.find((c) => c.fieldName === 'atDefaultShare').type).toBe('percent');
    expect(table.columns.find((c) => c.fieldName === 'required').type).toBe('boolean');

    const [phone, website, fax] = table.data;
    expect(phone.required).toBe(true);
    expect(phone.defaultShown).toBeNull();
    expect(phone.atDefaultShare).toBeNull();
    expect(website.defaultShown).toBe('Draft');
    expect(website.atDefaultShare).toBeCloseTo(0.4);
    expect(fax.defaultShown).toBe('c.Core_DataDictionary_ColFormula');
    expect(fax.atDefaultShare).toBeNull();
  });

  it('says an object over the size limit is not counted, and counts nothing', async () => {
    getPlan.mockResolvedValue({ ...PLAN, total: 2000000, tooLarge: true, fields: [] });
    const element = render();
    await choose(element, 'Account');

    expect(find(element, 'too-large').message).toContain('More than');
    expect(countFields).not.toHaveBeenCalled();
  });

  it('saves only the counted values and shows the saved count next', async () => {
    getPlan.mockResolvedValueOnce({ ...PLAN, chunkSize: 40, previousTakenAt: null, previous: [] });
    countFields.mockResolvedValue({ rows: [row('Phone', 80, 80.0)], failed: [] });
    saveCounts.mockResolvedValue(1);
    const element = render();
    await choose(element, 'Account');
    expect(find(element, 'never-saved')).not.toBeNull();

    getPlan.mockResolvedValueOnce({
      ...PLAN,
      previousTakenAt: '2026-10-13T08:00:00.000Z',
      previous: [row('Phone', 80, 80.0)]
    });
    find(element, 'save').click();
    await flush();

    expect(saveCounts).toHaveBeenCalledWith({
      objectName: 'Account',
      rows: [
        { fieldName: 'Phone', recordType: 'Organization', filled: 80, total: 100, sampled: false }
      ]
    });
    expect(find(element, 'notice').message).toContain('Saved 1 counts.');
    expect(find(element, 'results').data[0].change).toBe(0);
  });

  it('sorts by the chosen column', async () => {
    getPlan.mockResolvedValue({ ...PLAN, chunkSize: 40 });
    countFields.mockResolvedValue({
      rows: [row('Phone', 80, 80.0), row('Website', 10, 10.0)],
      failed: []
    });
    const element = render();
    await choose(element, 'Account');

    find(element, 'results').dispatchEvent(
      new CustomEvent('sort', { detail: { fieldName: 'share', sortDirection: 'asc' } })
    );
    await flush();

    expect(find(element, 'results').data.map((r) => r.fieldName)).toEqual(['Website', 'Phone']);

    find(element, 'results').dispatchEvent(
      new CustomEvent('rowaction', {
        detail: { action: { name: 'whereUsed' }, row: find(element, 'results').data[0] }
      })
    );
    expect(WhereUsedModal.open).toHaveBeenCalledWith(
      expect.objectContaining({ objectName: 'Account', fieldName: 'Website' })
    );
  });

  it('shows the server message when a count fails', async () => {
    getPlan.mockRejectedValue({ body: { message: 'You need the permission.' } });
    const element = render();
    await choose(element, 'Account');

    expect(find(element, 'error').message).toContain('You need the permission.');
  });
});

describe('c-field-utilization snapshot history', () => {
  const LATEST = '2026-10-04T08:00:00.000Z';
  const OLDER = '2026-09-20T08:00:00.000Z';
  const HISTORY = {
    snapshots: [
      {
        takenAt: LATEST,
        savedBy: 'Maria Lopez',
        rowCount: 112,
        fieldCount: 56,
        averagePercent: 42.5
      },
      { takenAt: OLDER, savedBy: 'Sam Rivera', rowCount: 100, fieldCount: 50, averagePercent: 30 }
    ],
    maxSnapshots: 50,
    canDelete: true
  };
  const COUNTED = { rows: [row('Phone', 80, 80.0)], failed: [] };

  const act = async (element, name, takenAt, extra = {}) => {
    find(element, 'history-table').dispatchEvent(
      new CustomEvent('rowaction', {
        detail: { action: { name }, row: { takenAt, rowCount: 112, ...extra } }
      })
    );
    await flush();
  };

  beforeEach(() => {
    getPlan.mockResolvedValue({ ...PLAN, chunkSize: 40, previousTakenAt: LATEST });
    countFields.mockResolvedValue(COUNTED);
    getHistory.mockResolvedValue(HISTORY);
    BarnConfirmModal.open.mockResolvedValue(true);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    getHistory.mockReset();
  });

  it('shows the empty state when nothing has been saved', async () => {
    getHistory.mockResolvedValue({ snapshots: [], maxSnapshots: 50, canDelete: true });
    const element = render();
    await choose(element, 'Account');

    expect(getHistory).toHaveBeenCalledWith({ objectName: 'Account' });
    expect(find(element, 'history-empty').heading).toContain('HistoryEmpty');
    expect(find(element, 'history-table')).toBeNull();
  });

  it('shows no history before an object is chosen', async () => {
    const element = render();
    await flush();

    expect(find(element, 'history')).toBeNull();
  });

  it('lists one row per snapshot with who saved it, its fields and its average fill rate', async () => {
    const element = render();
    await choose(element, 'Account');

    expect(find(element, 'history').textContent).toContain('HistoryTitle');
    const table = find(element, 'history-table');
    expect(table.data).toHaveLength(2);
    expect(table.data[0]).toMatchObject({
      savedBy: 'Maria Lopez',
      fieldCount: 56,
      isCompared: true
    });
    expect(table.data[0].averageShare).toBeCloseTo(0.425);
    expect(table.data[1].isCompared).toBe(false);
    expect(table.columns.map((c) => c.typeAttributes && c.typeAttributes.name)).toEqual([
      undefined,
      undefined,
      undefined,
      undefined,
      'compare',
      'view',
      'delete'
    ]);
    expect(find(element, 'history-limit')).toBeNull();
  });

  it('offers no Delete without delete access, and says when the list is cut off', async () => {
    getHistory.mockResolvedValue({ ...HISTORY, canDelete: false, maxSnapshots: 2 });
    const element = render();
    await choose(element, 'Account');

    const names = find(element, 'history-table').columns.map(
      (c) => c.typeAttributes && c.typeAttributes.name
    );
    expect(names).not.toContain('delete');
    expect(find(element, 'history-limit').textContent).toContain('2');
  });

  it('compares with the chosen snapshot: the Saved and Change columns follow it', async () => {
    getSnapshotRows.mockResolvedValue([row('Phone', 50, 50.0)]);
    const element = render();
    await choose(element, 'Account');
    expect(find(element, 'results').data[0].previousShare).toBeCloseTo(0.75);

    await act(element, 'compare', OLDER);

    expect(getSnapshotRows).toHaveBeenCalledWith({ objectName: 'Account', takenAt: OLDER });
    const first = find(element, 'results').data[0];
    expect(first.previousShare).toBeCloseTo(0.5);
    expect(first.change).toBe(30);
    const flags = find(element, 'history-table').data.map((r) => r.isCompared);
    expect(flags).toEqual([false, true]);
  });

  it('shows the fields of a snapshot and closes the view', async () => {
    getSnapshotRows.mockResolvedValue([row('Phone', 50, 50.0), row('Website', 10, 10.0)]);
    const element = render();
    await choose(element, 'Account');
    expect(find(element, 'snapshot-view')).toBeNull();

    await act(element, 'view', OLDER);

    expect(getSnapshotRows).toHaveBeenCalledWith({ objectName: 'Account', takenAt: OLDER });
    const rows = find(element, 'snapshot-rows').data;
    expect(rows).toHaveLength(2);
    expect(rows[0]).toMatchObject({
      objectLabel: 'Account',
      recordTypeLabel: 'Organization',
      fieldLabel: 'Phone'
    });
    expect(rows[0].share).toBeCloseTo(0.5);

    find(element, 'view-close').click();
    await flush();
    expect(find(element, 'snapshot-view')).toBeNull();
  });

  it('deletes a snapshot only after the person confirms, then refreshes', async () => {
    deleteSnapshot.mockResolvedValue(100);
    const element = render();
    await choose(element, 'Account');
    getPlan.mockClear();
    getHistory.mockClear();

    BarnConfirmModal.open.mockResolvedValueOnce(false);
    await act(element, 'delete', OLDER);
    expect(deleteSnapshot).not.toHaveBeenCalled();

    await act(element, 'delete', OLDER, { rowCount: 100 });

    const dialog = BarnConfirmModal.open.mock.calls[1][0];
    expect(dialog.confirmVariant).toBe('destructive');
    expect(dialog.message).toContain('100');
    expect(deleteSnapshot).toHaveBeenCalledWith({ objectName: 'Account', takenAt: OLDER });
    expect(getPlan).toHaveBeenCalledWith({ objectName: 'Account' });
    expect(getHistory).toHaveBeenCalledWith({ objectName: 'Account' });
    expect(find(element, 'notice').message).toContain('Deleted');
  });

  it('shows the server message when a delete is refused', async () => {
    deleteSnapshot.mockRejectedValue({ body: { message: 'No delete access.' } });
    const element = render();
    await choose(element, 'Account');

    await act(element, 'delete', OLDER);

    expect(find(element, 'error').message).toContain('No delete access.');
  });
});
