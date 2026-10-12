import { createElement } from 'lwc';
import BulkUpdateHistory from 'c/bulkUpdateHistory';
import getPage from '@salesforce/apex/BulkUpdateController.getPage';
import undoUpdate from '@salesforce/apex/BulkUpdateController.undo';

jest.mock('@salesforce/apex/BulkUpdateController.getPage', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkUpdateController.undo', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_BulkUpdate_Summary',
  () => ({ default: '{0} matched: {1} updated, {2} unchanged, {3} failed.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_BulkUpdate_UndoConfirm',
  () => ({ default: 'Undo puts back {0}.' }),
  { virtual: true }
);

const FINISHED = {
  recordId: 'a0B000000000001',
  name: 'IB-000001',
  status: 'Complete',
  objectLabel: 'Contacts',
  matched: 200,
  updated: 200,
  unchanged: 0,
  failed: 0,
  running: false,
  canUndo: true,
  updatesToUndo: 200,
  failures: []
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function render() {
  const element = createElement('c-bulk-update-history', { is: BulkUpdateHistory });
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

describe('c-bulk-update-history', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('says so when there are no bulk updates', async () => {
    getPage.mockResolvedValue({ runLimit: 48000, maxChanges: 5, jobs: [] });
    const element = await render();

    expect(element.shadowRoot.querySelector('[data-id="no-jobs"]')).not.toBeNull();
    expect(element.shadowRoot.querySelectorAll('[data-id="job-row"]')).toHaveLength(0);
  });

  it('lists recent bulk updates and undoes one once its number is typed', async () => {
    getPage.mockResolvedValue({ runLimit: 48000, maxChanges: 5, jobs: [FINISHED] });
    undoUpdate.mockResolvedValue({ ...FINISHED, status: 'Undoing', canUndo: false });
    const element = await render();

    const rows = element.shadowRoot.querySelectorAll('[data-id="job-row"]');
    expect(rows).toHaveLength(1);
    expect(rows[0].textContent).toContain('200 matched: 200 updated, 0 unchanged, 0 failed.');
    element.shadowRoot.querySelector(`[data-id="${FINISHED.recordId}"]`).click();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="undo-line"]').textContent).toBe(
      'Undo puts back 200.'
    );
    const confirm = element.shadowRoot.querySelector('[data-id="undo-start"]');
    await change(element.shadowRoot.querySelector('[data-id="undo-confirm"]'), '199');
    expect(confirm.disabled).toBe(true);
    await change(element.shadowRoot.querySelector('[data-id="undo-confirm"]'), '200');
    expect(confirm.disabled).toBe(false);
    confirm.click();
    await flush();

    expect(undoUpdate).toHaveBeenCalledWith({
      jobId: FINISHED.recordId,
      confirmedUpdates: 200
    });
    expect(element.shadowRoot.querySelector('[data-id="undo-box"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="notice-message"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector(`[data-id="${FINISHED.recordId}"]`)).toBeNull();
  });

  it('shows the server refusal as it is', async () => {
    getPage.mockResolvedValue({ runLimit: 48000, maxChanges: 5, jobs: [FINISHED] });
    undoUpdate.mockRejectedValue({
      body: { message: 'This bulk update can no longer be undone.' }
    });
    const element = await render();

    element.shadowRoot.querySelector(`[data-id="${FINISHED.recordId}"]`).click();
    await flush();
    await change(element.shadowRoot.querySelector('[data-id="undo-confirm"]'), '200');
    element.shadowRoot.querySelector('[data-id="undo-start"]').click();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error-message"]').textContent).toBe(
      'This bulk update can no longer be undone.'
    );
  });

  it('reads the list again on refresh', async () => {
    getPage.mockResolvedValue({ runLimit: 48000, maxChanges: 5, jobs: [] });
    const element = await render();
    getPage.mockResolvedValue({ runLimit: 48000, maxChanges: 5, jobs: [FINISHED] });

    element.shadowRoot.querySelector('[data-id="refresh"]').click();
    await flush();
    await flush();

    expect(getPage).toHaveBeenCalledTimes(2);
    expect(element.shadowRoot.querySelectorAll('[data-id="job-row"]')).toHaveLength(1);
  });
});
