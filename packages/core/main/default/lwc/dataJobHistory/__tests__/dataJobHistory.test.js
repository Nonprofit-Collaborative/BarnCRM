import { createElement } from 'lwc';
import DataJobHistory from 'c/dataJobHistory';
import getRecentBatches from '@salesforce/apex/ImportController.getRecentBatches';
import previewUndo from '@salesforce/apex/ImportController.previewUndo';
import startUndo from '@salesforce/apex/ImportController.startUndo';
import getUpdatePage from '@salesforce/apex/BulkUpdateController.getPage';
import undoUpdate from '@salesforce/apex/BulkUpdateController.undo';
import getDeletePage from '@salesforce/apex/BulkDeleteController.getPage';
import undoDelete from '@salesforce/apex/BulkDeleteController.undo';

import findToolStateKey from '@salesforce/apex/DataManagerController.findToolStateKey';

jest.mock(
  '@salesforce/apex/DataManagerController.findToolStateKey',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
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
    return { NavigationMixin, __esModule: true };
  },
  { virtual: true }
);

jest.mock('@salesforce/customPermission/Manage_BarnCRM_Settings', () => ({ default: true }), {
  virtual: true
});
jest.mock('@salesforce/customPermission/Bulk_Update_Records', () => ({ default: true }), {
  virtual: true
});
jest.mock('@salesforce/customPermission/Bulk_Delete_Records', () => ({ default: true }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.getRecentBatches', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.previewUndo', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.startUndo', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkUpdateController.getPage', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkUpdateController.undo', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkDeleteController.getPage', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkDeleteController.undo', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_BulkUpdate_UndoConfirm',
  () => ({ default: 'Puts back {0}.' }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/label/c.Core_BulkDelete_UndoConfirm',
  () => ({ default: 'Brings back {0}.' }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/label/c.Core_DataJobs_ImportSummaryOne',
  () => ({ default: '{0} row: {1} created, {2} updated, {3} matched, {4} rejected.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_DataJobs_ImportSummary',
  () => ({ default: '{0} rows: {1} created, {2} updated, {3} matched, {4} rejected.' }),
  { virtual: true }
);

const IMPORT_JOB = {
  id: 'a0B000000000001',
  name: 'IB-000001',
  fileName: 'donors.csv',
  status: 'Complete',
  rowCount: 5,
  created: 5,
  updated: 0,
  matched: 0,
  rejected: 0,
  startedAt: '2026-10-01T10:00:00.000Z',
  undoDeadline: '2026-10-31T00:00:00.000Z',
  canUndo: true
};

const UPDATE_JOB = {
  recordId: 'a0B000000000002',
  name: 'IB-000002',
  status: 'Complete',
  objectLabel: 'Contact',
  matched: 37,
  updated: 37,
  unchanged: 0,
  failed: 0,
  running: false,
  canUndo: true,
  updatesToUndo: 37,
  startedAt: '2026-10-02T10:00:00.000Z',
  undoDeadline: '2026-11-01T00:00:00.000Z'
};

const DELETE_JOB = {
  recordId: 'a0B000000000003',
  name: 'IB-000003',
  status: 'Complete',
  objectLabel: 'Contact',
  matched: 4,
  deleted: 4,
  failed: 0,
  running: false,
  canUndo: true,
  recordsToUndo: 4,
  startedAt: '2026-10-03T10:00:00.000Z',
  undoDeadline: '2026-10-17T00:00:00.000Z'
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

function one(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

/** Chooses Undo in a job row's menu. */
function pickUndo(element, id) {
  one(element, id).dispatchEvent(new CustomEvent('select', { detail: { value: 'undo' } }));
}

function rows(element) {
  return Array.from(element.shadowRoot.querySelectorAll('[data-id="job-row"]'));
}

async function render(kinds) {
  const element = createElement('c-data-job-history', { is: DataJobHistory });
  if (kinds) {
    element.kinds = kinds;
  }
  document.body.appendChild(element);
  await flush();
  await flush();
  return element;
}

async function change(target, value) {
  target.value = value;
  target.dispatchEvent(new CustomEvent('change', { detail: { value } }));
  await flush();
}

describe('c-data-job-history', () => {
  beforeEach(() => {
    getRecentBatches.mockResolvedValue([IMPORT_JOB]);
    getUpdatePage.mockResolvedValue({ allowed: true, jobs: [UPDATE_JOB] });
    getDeletePage.mockResolvedValue({ allowed: true, jobs: [DELETE_JOB] });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists every kind of job in one list, newest first', async () => {
    const element = await render();

    expect(getRecentBatches).toHaveBeenCalledWith({ howMany: 10 });
    expect(rows(element).map((row) => row.dataset.kind)).toEqual(['Delete', 'Update', 'Import']);
    expect(rows(element)[2].textContent).toContain('5 rows: 5 created');
    expect(one(element, 'filter').options.map((option) => option.value)).toEqual([
      'all',
      'Import',
      'Update',
      'Delete'
    ]);
  });

  it('says "1 row" for a one-row import', async () => {
    getRecentBatches.mockResolvedValue([{ ...IMPORT_JOB, rowCount: 1, created: 1 }]);
    const element = await render();

    const text = rows(element).find((row) => row.dataset.kind === 'Import').textContent;
    expect(text).toContain('1 row: 1 created');
    expect(text).not.toContain('1 rows');
  });

  it('filters the list to one kind', async () => {
    const element = await render();

    await change(one(element, 'filter'), 'Import');

    expect(rows(element).map((row) => row.dataset.kind)).toEqual(['Import']);
  });

  it('reads only the kinds its placement names, with no filter for one kind', async () => {
    const element = await render('Import');

    expect(getRecentBatches).toHaveBeenCalled();
    expect(getUpdatePage).not.toHaveBeenCalled();
    expect(getDeletePage).not.toHaveBeenCalled();
    expect(rows(element)).toHaveLength(1);
    expect(one(element, 'filter')).toBeNull();
  });

  it('leaves out a bulk kind the person is not allowed to run', async () => {
    getDeletePage.mockResolvedValue({ allowed: false, jobs: [] });
    const element = await render();

    expect(rows(element).map((row) => row.dataset.kind)).toEqual(['Update', 'Import']);
    expect(one(element, 'filter').options.map((option) => option.value)).toEqual([
      'all',
      'Import',
      'Update'
    ]);
  });

  it('renders nothing when the person may see none of the kinds', async () => {
    getUpdatePage.mockResolvedValue({ allowed: false, jobs: [] });
    getDeletePage.mockResolvedValue({ allowed: false, jobs: [] });
    const element = await render('Update,Delete');

    expect(element.shadowRoot.querySelector('lightning-card')).toBeNull();
  });

  it('opens Find, where a bulk update starts, with the note that says where (D-135)', async () => {
    const element = await render('Update,Delete');
    findToolStateKey.emit('ns__tool');
    one(element, 'open-find').click();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Find' },
      state: { ns__tool: 'update' }
    });
  });

  it('says so when there are no jobs yet', async () => {
    getRecentBatches.mockResolvedValue([]);
    getUpdatePage.mockResolvedValue({ allowed: true, jobs: [] });
    getDeletePage.mockResolvedValue({ allowed: true, jobs: [] });
    const element = await render();

    expect(one(element, 'no-jobs')).not.toBeNull();
  });

  it('shows the server error when a list cannot be read', async () => {
    getUpdatePage.mockRejectedValue({ body: { message: 'No access' } });
    const element = await render();

    expect(one(element, 'error-message').textContent).toBe('No access');
  });

  it('shows each status as a badge and keeps Undo in a row menu', async () => {
    getUpdatePage.mockResolvedValue({ allowed: true, jobs: [{ ...UPDATE_JOB, status: 'Failed' }] });
    getDeletePage.mockResolvedValue({ allowed: true, jobs: [] });
    const element = await render();

    const badges = element.shadowRoot.querySelectorAll('[data-id="status-badge"]');
    expect(badges.length).toBeGreaterThan(0);
    const failed = Array.from(badges).find((badge) => badge.label === 'Failed');
    expect(failed.className).toContain('slds-theme_error');
    expect(one(element, UPDATE_JOB.recordId).tagName.toLowerCase()).toBe('lightning-button-menu');
    expect(element.shadowRoot.querySelector('lightning-menu-item').value).toBe('undo');
  });

  it('undoes a bulk update only once the number is typed', async () => {
    undoUpdate.mockResolvedValue({ ...UPDATE_JOB, status: 'Undoing', canUndo: false });
    const element = await render();

    pickUndo(element, UPDATE_JOB.recordId);
    await flush();
    expect(one(element, 'undo-line').textContent).toBe('Puts back 37.');
    expect(one(element, 'bulk-undo-start').disabled).toBe(true);

    await change(one(element, 'undo-confirm'), '37');
    expect(one(element, 'bulk-undo-start').disabled).toBe(false);
    one(element, 'bulk-undo-start').click();
    await flush();

    expect(undoUpdate).toHaveBeenCalledWith({ jobId: UPDATE_JOB.recordId, confirmedUpdates: 37 });
    expect(one(element, 'bulk-undo-box')).toBeNull();
    expect(one(element, 'notice-message')).not.toBeNull();
    expect(one(element, UPDATE_JOB.recordId)).toBeNull();
  });

  it('keeps reading the list after an undo until the job leaves Undoing (FINDB-19)', async () => {
    const pending = [];
    const realSetTimeout = window.setTimeout;
    jest.spyOn(window, 'setTimeout').mockImplementation((callback, delay, ...args) => {
      if (delay === 3000 || delay === 10000) {
        pending.push(callback);
        return pending.length;
      }
      return realSetTimeout.call(window, callback, delay, ...args);
    });
    undoUpdate.mockResolvedValue({ ...UPDATE_JOB, status: 'Undoing', running: true });
    const element = await render();
    pickUndo(element, UPDATE_JOB.recordId);
    await flush();
    await change(one(element, 'undo-confirm'), '37');
    one(element, 'bulk-undo-start').click();
    await flush();
    expect(pending).toHaveLength(1);
    const readsBefore = getUpdatePage.mock.calls.length;

    // Still running: read again and keep polling.
    getUpdatePage.mockResolvedValue({
      allowed: true,
      jobs: [{ ...UPDATE_JOB, status: 'Undoing', running: true }]
    });
    pending.pop()();
    await flush();
    expect(getUpdatePage.mock.calls.length).toBe(readsBefore + 1);
    expect(pending).toHaveLength(1);

    // Done: the row shows its final status and polling stops.
    getUpdatePage.mockResolvedValue({
      allowed: true,
      jobs: [{ ...UPDATE_JOB, status: 'Undone', running: false, canUndo: false }]
    });
    pending.pop()();
    await flush();
    expect(getUpdatePage.mock.calls.length).toBe(readsBefore + 2);
    expect(pending).toHaveLength(0);
    const badge = Array.from(element.shadowRoot.querySelectorAll('[data-id="status-badge"]')).find(
      (candidate) => candidate.label === 'Undone'
    );
    expect(badge).toBeDefined();
    expect(badge.className).toContain('slds-theme_success');
    jest.restoreAllMocks();
  });

  it('undoes a bulk delete with the records it brings back', async () => {
    undoDelete.mockResolvedValue({ ...DELETE_JOB, status: 'Undoing', canUndo: false });
    const element = await render();

    pickUndo(element, DELETE_JOB.recordId);
    await flush();
    expect(one(element, 'undo-line').textContent).toBe('Brings back 4.');
    await change(one(element, 'undo-confirm'), '4');
    one(element, 'bulk-undo-start').click();
    await flush();

    expect(undoDelete).toHaveBeenCalledWith({ jobId: DELETE_JOB.recordId, confirmedRecords: 4 });
  });

  it('undoes an import after showing what it would remove and put back', async () => {
    previewUndo.mockResolvedValue({
      allowed: true,
      people: 5,
      households: 3,
      organizations: 0,
      updates: 2,
      total: 8,
      others: [{ objectName: 'Gift__c', label: 'Gifts', count: 4 }]
    });
    startUndo.mockResolvedValue({ ...IMPORT_JOB, status: 'Undoing' });
    const element = await render();

    pickUndo(element, IMPORT_JOB.id);
    await flush();
    await flush();

    expect(previewUndo).toHaveBeenCalledWith({ batchId: IMPORT_JOB.id });
    expect(one(element, 'people').textContent).toContain('5');
    expect(one(element, 'other-Gift__c').textContent).toContain('Gifts');
    expect(one(element, 'import-undo-start').disabled).toBe(false);

    one(element, 'import-undo-start').click();
    await flush();
    await flush();

    expect(startUndo).toHaveBeenCalledWith({ batchId: IMPORT_JOB.id, confirmedTotal: 8 });
    expect(getRecentBatches).toHaveBeenCalledTimes(2);
    expect(one(element, 'notice-message')).not.toBeNull();
  });

  it('shows why an import cannot be undone and keeps the button off', async () => {
    previewUndo.mockResolvedValue({ allowed: false, reason: 'The time to undo ended.' });
    const element = await render();

    pickUndo(element, IMPORT_JOB.id);
    await flush();
    await flush();

    expect(one(element, 'error-message').textContent).toBe('The time to undo ended.');
    expect(one(element, 'import-undo-start').disabled).toBe(true);

    one(element, 'undo-cancel').click();
    await flush();
    expect(one(element, 'import-undo-box')).toBeNull();
  });

  it('reads the lists again on Refresh', async () => {
    const element = await render();

    one(element, 'refresh').click();
    await flush();
    await flush();

    expect(getUpdatePage).toHaveBeenCalledTimes(2);
  });

  it('lists the person own bulk jobs, and everyone else too for someone allowed who asks', async () => {
    let element = await render();
    expect(getUpdatePage).toHaveBeenCalledWith({ everyone: false });
    expect(getDeletePage).toHaveBeenCalledWith({ everyone: false });
    expect(one(element, 'everyone')).toBeNull();
    document.body.removeChild(element);

    getUpdatePage.mockResolvedValue({ allowed: true, canSeeEveryone: true, jobs: [] });
    element = await render();
    const everyone = one(element, 'everyone');
    everyone.checked = true;
    everyone.dispatchEvent(new CustomEvent('change'));
    await flush();
    await flush();

    expect(getUpdatePage).toHaveBeenLastCalledWith({ everyone: true });
    expect(getDeletePage).toHaveBeenLastCalledWith({ everyone: true });
  });
});
