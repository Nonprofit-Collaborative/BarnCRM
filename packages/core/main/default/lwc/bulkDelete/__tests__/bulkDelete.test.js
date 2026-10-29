import { createElement } from 'lwc';
import BulkDelete from 'c/bulkDelete';
import previewDelete from '@salesforce/apex/BulkDeleteController.preview';
import startDelete from '@salesforce/apex/BulkDeleteController.start';
import getJob from '@salesforce/apex/BulkDeleteController.getJob';
import previewFile from '@salesforce/apex/BulkDeleteController.previewFile';
import startFile from '@salesforce/apex/BulkDeleteController.startFile';
import backupPage from '@salesforce/apex/BulkDeleteController.backupPage';

jest.mock('@salesforce/apex/BulkDeleteController.preview', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkDeleteController.start', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkDeleteController.getJob', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkDeleteController.previewFile', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkDeleteController.startFile', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkDeleteController.backupPage', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_BulkDelete_BackupDone',
  () => ({ default: 'Downloaded {0} records.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_BulkDelete_PreviewCount',
  () => ({ default: '{0} {1} match. The first ones:' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_BulkDelete_DeleteButton',
  () => ({ default: 'Delete {0} records' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_BulkDelete_Summary',
  () => ({ default: '{0} matched: {1} deleted, {2} refused.' }),
  { virtual: true }
);

const QUERY = JSON.stringify({ version: 1, object: 'Contact', fields: ['LastName'] });

const PREVIEW = {
  count: 200,
  runLimit: 10000,
  objectLabel: 'Contacts',
  soql: 'SELECT Id FROM Contact',
  sample: [
    { recordId: '003000000000001', name: 'Person 0' },
    { recordId: '003000000000002', name: 'Person 1' }
  ],
  cascades: ['Program Enrollments'],
  undoDeadline: '2026-10-27T00:00:00.000Z'
};

const RUNNING = {
  recordId: 'a0B000000000001',
  name: 'IB-000001',
  status: 'Committing',
  matched: 200,
  deleted: 0,
  failed: 0,
  running: true,
  chunksDone: 0,
  chunksTotal: 1,
  canUndo: false,
  recordsToUndo: 0,
  failures: []
};

const FINISHED = {
  ...RUNNING,
  status: 'Complete',
  deleted: 199,
  failed: 1,
  running: false,
  chunksDone: 1,
  canUndo: true,
  recordsToUndo: 199,
  failures: [{ recordId: '003000000000009', reason: 'Has gifts' }]
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

/**
 * Holds the poll timers c/jobPoller sets (3 or 10 seconds) so a test runs them by hand; every
 * other timer, such as flush, runs for real. `next()` returns the callback of the latest poll.
 */
function capturePolls() {
  const pending = [];
  const realSetTimeout = window.setTimeout;
  jest.spyOn(window, 'setTimeout').mockImplementation((callback, delay, ...args) => {
    if (delay === 3000 || delay === 10000) {
      pending.push(callback);
      return pending.length;
    }
    return realSetTimeout.call(window, callback, delay, ...args);
  });
  return { next: () => pending.pop() };
}

function one(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

async function render() {
  const element = createElement('c-bulk-delete', { is: BulkDelete });
  element.queryJson = QUERY;
  document.body.appendChild(element);
  await flush();
  return element;
}

async function change(target, value) {
  target.value = value;
  target.dispatchEvent(new CustomEvent('change', { detail: { value } }));
  await flush();
}

describe('c-bulk-delete', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    jest.restoreAllMocks();
  });

  it('previews the count, the first names and what is deleted with them', async () => {
    previewDelete.mockResolvedValue(PREVIEW);
    const element = await render();
    one(element, 'preview').click();
    await flush();

    expect(previewDelete).toHaveBeenCalledWith({ queryJson: QUERY });
    expect(one(element, 'preview-line').textContent).toBe('200 Contacts match. The first ones:');
    const names = [...element.shadowRoot.querySelectorAll('[data-id="sample-row"]')];
    expect(names.map((row) => row.textContent)).toEqual(['Person 0', 'Person 1']);
    expect(one(element, 'cascade').label).toBe('Program Enrollments');
    expect(one(element, 'path').currentStep).toBe('confirm');
    expect(one(element, 'start').label).toBe('Delete 200 records');
  });

  it('starts only once the count is typed, then shows progress and the result', async () => {
    previewDelete.mockResolvedValue({ ...PREVIEW, cascades: [] });
    startDelete.mockResolvedValue(RUNNING);
    getJob.mockResolvedValue(FINISHED);
    const polls = capturePolls();
    const element = await render();
    one(element, 'preview').click();
    await flush();

    expect(one(element, 'cascades')).toBeNull();
    expect(one(element, 'start').disabled).toBe(true);
    await change(one(element, 'confirm'), '199');
    expect(one(element, 'start').disabled).toBe(true);
    await change(one(element, 'confirm'), ' 200 ');
    expect(one(element, 'start').disabled).toBe(false);

    one(element, 'start').click();
    await flush();
    expect(startDelete).toHaveBeenCalledWith({ queryJson: QUERY, confirmedCount: 200 });
    expect(one(element, 'preview-box')).toBeNull();
    expect(one(element, 'notice-message')).not.toBeNull();

    polls.next()();
    await flush();
    expect(getJob).toHaveBeenCalledWith({ jobId: 'a0B000000000001' });
    expect(one(element, 'job-summary').textContent).toBe('200 matched: 199 deleted, 1 refused.');
    expect(one(element, 'undo-from-tab')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="job"] li').textContent).toBe(
      '003000000000009: Has gifts'
    );
  });

  it('retries one failed progress read, and reports the error after a second (FINDB-19)', async () => {
    previewDelete.mockResolvedValue({ ...PREVIEW, cascades: [] });
    startDelete.mockResolvedValue(RUNNING);
    getJob.mockRejectedValue({ body: { message: 'Connection lost' } });
    const polls = capturePolls();
    const element = await render();
    one(element, 'preview').click();
    await flush();
    await change(one(element, 'confirm'), '200');
    one(element, 'start').click();
    await flush();

    polls.next()();
    await flush();
    expect(one(element, 'error-message')).toBeNull();

    polls.next()();
    await flush();
    expect(getJob).toHaveBeenCalledTimes(2);
    expect(one(element, 'error-message').textContent).toBe('Connection lost');
  });

  it('deletes what a delete by file dry run found, sending the batch and the count', async () => {
    previewFile.mockResolvedValue(PREVIEW);
    startFile.mockResolvedValue(RUNNING);
    jest.spyOn(window, 'setInterval').mockImplementation(() => 1);
    const element = createElement('c-bulk-delete', { is: BulkDelete });
    element.batchId = 'a0B000000000009';
    document.body.appendChild(element);
    await flush();
    expect(one(element, 'intro').textContent).toBe('c.Core_BulkDelete_FileIntro');

    one(element, 'preview').click();
    await flush();
    expect(previewFile).toHaveBeenCalledWith({ batchId: 'a0B000000000009' });
    expect(previewDelete).not.toHaveBeenCalled();
    expect(one(element, 'cascade').label).toBe('Program Enrollments');

    await change(one(element, 'confirm'), '200');
    one(element, 'start').click();
    await flush();
    expect(startFile).toHaveBeenCalledWith({ batchId: 'a0B000000000009', confirmedCount: 200 });
    expect(startDelete).not.toHaveBeenCalled();
    expect(one(element, 'notice-message')).not.toBeNull();
  });

  it('downloads every record page by page as CSV before anything is deleted', async () => {
    previewDelete.mockResolvedValue(PREVIEW);
    const columns = [
      { fieldName: 'Id', label: 'Contact ID' },
      { fieldName: 'LastName', label: 'Last Name' }
    ];
    backupPage
      .mockResolvedValueOnce({
        objectName: 'Contact',
        columns,
        rows: [{ Id: '003000000000001', LastName: 'Person 0' }],
        lastId: '003000000000001',
        done: false
      })
      .mockResolvedValueOnce({
        objectName: 'Contact',
        columns,
        rows: [{ Id: '003000000000002', LastName: '=Person 1' }],
        lastId: '003000000000002',
        done: true
      });
    let saved;
    URL.createObjectURL = jest.fn((blob) => {
      saved = blob;
      return 'blob:backup';
    });
    URL.revokeObjectURL = jest.fn();
    const clicked = jest.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});
    const element = await render();
    one(element, 'preview').click();
    await flush();

    one(element, 'backup').click();
    await flush();
    expect(backupPage).toHaveBeenNthCalledWith(1, {
      queryJson: QUERY,
      batchId: null,
      afterId: null
    });
    expect(backupPage).toHaveBeenNthCalledWith(2, {
      queryJson: QUERY,
      batchId: null,
      afterId: '003000000000001'
    });
    expect(clicked).toHaveBeenCalledTimes(1);
    const text = await new Promise((resolve) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result);
      reader.readAsText(saved);
    });
    expect(text).toContain('Contact ID,Last Name\r\n003000000000001,Person 0\r\n');
    expect(text).toContain("003000000000002,'=Person 1");
    expect(one(element, 'notice-message').textContent).toBe('Downloaded 2 records.');
    expect(startDelete).not.toHaveBeenCalled();
  });

  it('shows a refusal and offers no delete', async () => {
    previewDelete.mockRejectedValue({ body: { message: 'More than 10000 records match.' } });
    const element = await render();
    one(element, 'preview').click();
    await flush();

    expect(one(element, 'error-message').textContent).toBe('More than 10000 records match.');
    expect(one(element, 'start')).toBeNull();
  });

  it('tells Find to close it', async () => {
    const element = await render();
    const closed = jest.fn();
    element.addEventListener('close', closed);
    one(element, 'close').click();
    await flush();
    expect(closed).toHaveBeenCalledTimes(1);
  });
});
