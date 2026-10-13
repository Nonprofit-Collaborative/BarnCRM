import { createElement } from 'lwc';
import BulkDeleteHistory from 'c/bulkDeleteHistory';
import getPage from '@salesforce/apex/BulkDeleteController.getPage';
import undoDelete from '@salesforce/apex/BulkDeleteController.undo';

jest.mock('@salesforce/apex/BulkDeleteController.getPage', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkDeleteController.undo', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_BulkDelete_Summary',
  () => ({ default: '{0} matched: {1} deleted, {2} refused.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_BulkDelete_UndoConfirm',
  () => ({ default: 'Undo brings back {0}.' }),
  { virtual: true }
);

const FINISHED = {
  recordId: 'a0B000000000001',
  name: 'IB-000001',
  status: 'Complete',
  matched: 200,
  deleted: 200,
  failed: 0,
  running: false,
  canUndo: true,
  recordsToUndo: 200,
  undoDeadline: '2026-10-27T00:00:00.000Z',
  failures: []
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

function one(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

async function render() {
  const element = createElement('c-bulk-delete-history', { is: BulkDeleteHistory });
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

describe('c-bulk-delete-history', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows nothing to a person without the bulk delete permissions', async () => {
    getPage.mockResolvedValue({ allowed: false, jobs: [] });
    const element = await render();
    expect(element.shadowRoot.querySelector('lightning-card')).toBeNull();
  });

  it('lists recent bulk deletes, or says there are none', async () => {
    getPage.mockResolvedValue({ allowed: true, runLimit: 10000, jobs: [] });
    const empty = await render();
    expect(one(empty, 'no-jobs')).not.toBeNull();
    empty.remove();

    getPage.mockResolvedValue({ allowed: true, runLimit: 10000, jobs: [FINISHED] });
    const element = await render();
    const rows = element.shadowRoot.querySelectorAll('[data-id="job-row"]');
    expect(rows.length).toBe(1);
    expect(rows[0].textContent).toContain('200 matched: 200 deleted, 0 refused.');
  });

  it('undoes only once the number of records is typed', async () => {
    getPage.mockResolvedValue({ allowed: true, runLimit: 10000, jobs: [FINISHED] });
    undoDelete.mockResolvedValue({ ...FINISHED, status: 'Undoing', canUndo: false });
    const element = await render();
    one(element, FINISHED.recordId).click();
    await flush();

    expect(one(element, 'undo-line').textContent).toBe('Undo brings back 200.');
    expect(one(element, 'undo-start').disabled).toBe(true);
    await change(one(element, 'undo-confirm'), '20');
    expect(one(element, 'undo-start').disabled).toBe(true);
    await change(one(element, 'undo-confirm'), '200');
    expect(one(element, 'undo-start').disabled).toBe(false);

    one(element, 'undo-start').click();
    await flush();
    expect(undoDelete).toHaveBeenCalledWith({
      jobId: FINISHED.recordId,
      confirmedRecords: 200
    });
    expect(one(element, 'undo-box')).toBeNull();
    expect(one(element, 'notice-message')).not.toBeNull();
    expect(one(element, FINISHED.recordId)).toBeNull();
  });

  it('shows why an undo was refused', async () => {
    getPage.mockResolvedValue({ allowed: true, runLimit: 10000, jobs: [FINISHED] });
    undoDelete.mockRejectedValue({ body: { message: 'You confirmed 200 records.' } });
    const element = await render();
    one(element, FINISHED.recordId).click();
    await flush();
    await change(one(element, 'undo-confirm'), '200');
    one(element, 'undo-start').click();
    await flush();
    expect(one(element, 'error-message').textContent).toBe('You confirmed 200 records.');
  });

  it('lists the person own jobs, and everyone else too for someone allowed who asks', async () => {
    getPage.mockResolvedValue({ allowed: true, canSeeEveryone: false, jobs: [] });
    let element = await render();
    expect(getPage).toHaveBeenCalledWith({ everyone: false });
    expect(element.shadowRoot.querySelector('[data-id="everyone"]')).toBeNull();
    document.body.removeChild(element);

    getPage.mockResolvedValue({ allowed: true, canSeeEveryone: true, jobs: [] });
    element = await render();
    const everyone = element.shadowRoot.querySelector('[data-id="everyone"]');
    everyone.checked = true;
    everyone.dispatchEvent(new CustomEvent('change'));
    await flush();
    expect(getPage).toHaveBeenLastCalledWith({ everyone: true });
  });
});
