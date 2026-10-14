import { createElement } from 'lwc';
import BulkUpdate from 'c/bulkUpdate';
import getPage from '@salesforce/apex/BulkUpdateController.getPage';
import getTargets from '@salesforce/apex/BulkUpdateController.getTargets';
import getCopySources from '@salesforce/apex/BulkUpdateController.getCopySources';
import previewUpdate from '@salesforce/apex/BulkUpdateController.preview';
import startUpdate from '@salesforce/apex/BulkUpdateController.start';
import getJob from '@salesforce/apex/BulkUpdateController.getJob';

jest.mock('@salesforce/apex/BulkUpdateController.getPage', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkUpdateController.getTargets', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkUpdateController.getCopySources', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkUpdateController.preview', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkUpdateController.start', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkUpdateController.getJob', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_BulkUpdate_PreviewCount',
  () => ({ default: '{0} records match.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_BulkUpdate_UpdateButton',
  () => ({ default: 'Update {0} records' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_BulkUpdate_Summary',
  () => ({ default: '{0} matched: {1} updated, {2} unchanged, {3} failed.' }),
  { virtual: true }
);

const QUERY = JSON.stringify({ version: 1, object: 'Contact', fields: ['LastName'] });

const TARGETS = [
  { apiName: 'Title', label: 'Title', dataType: 'string', nillable: true, picklistValues: [] },
  {
    apiName: 'Personal_Email__c',
    label: 'Personal Email',
    dataType: 'email',
    nillable: true,
    picklistValues: []
  }
];

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

async function render(queryJson) {
  const element = createElement('c-bulk-update', { is: BulkUpdate });
  element.queryJson = queryJson;
  document.body.appendChild(element);
  await flush();
  await flush();
  return element;
}

function byPart(element, part) {
  return element.shadowRoot.querySelector(`[data-part="${part}"]`);
}

async function change(target, value) {
  target.value = value;
  target.dispatchEvent(new CustomEvent('change', { detail: { value } }));
  await flush();
}

describe('c-bulk-update', () => {
  beforeEach(() => {
    getTargets.mockResolvedValue(TARGETS);
  });

  it('opens on one server read and allows five changes', async () => {
    const element = await render(QUERY);
    expect(getPage).not.toHaveBeenCalled();
    expect(getTargets).toHaveBeenCalledTimes(1);

    const add = element.shadowRoot.querySelector('[data-id="add-change"]');
    for (let i = 0; i < 4; i++) {
      expect(add.disabled).toBe(false);
      add.click();
      // eslint-disable-next-line no-await-in-loop
      await flush();
    }
    expect(add.disabled).toBe(true);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    jest.restoreAllMocks();
  });

  it('previews, needs the count typed, starts and follows the job to its end', async () => {
    previewUpdate.mockResolvedValue({
      count: 200,
      runLimit: 48000,
      objectLabel: 'Contacts',
      sample: [
        {
          recordId: '003000000000001',
          name: 'Ana Ramirez',
          changes: [{ label: 'Title', before: 'Volunteer', after: 'Coordinator' }]
        }
      ]
    });
    startUpdate.mockResolvedValue({ ...FINISHED, status: 'Committing', running: true });
    getJob.mockResolvedValue(FINISHED);
    const element = await render(QUERY);
    expect(getTargets).toHaveBeenCalledWith({ objectName: 'Contact' });

    await change(byPart(element, 'field'), 'Title');
    await change(byPart(element, 'value'), 'Coordinator');
    element.shadowRoot.querySelector('[data-id="preview"]').click();
    await flush();

    expect(previewUpdate).toHaveBeenCalledWith({
      queryJson: QUERY,
      changesJson: JSON.stringify([{ field: 'Title', action: 'set', value: 'Coordinator' }])
    });
    expect(element.shadowRoot.querySelector('[data-id="preview-line"]').textContent).toBe(
      '200 records match.'
    );
    expect(element.shadowRoot.querySelectorAll('[data-id="sample-row"]')).toHaveLength(1);
    expect(
      element.shadowRoot.querySelector('[data-id="preview-table"]').getAttribute('aria-label')
    ).toBeTruthy();
    const start = element.shadowRoot.querySelector('[data-id="start"]');
    expect(start.disabled).toBe(true);

    const polls = capturePolls();
    await change(element.shadowRoot.querySelector('[data-id="confirm"]'), '200');
    expect(start.disabled).toBe(false);
    start.click();
    await flush();
    expect(startUpdate).toHaveBeenCalledWith(
      expect.objectContaining({ queryJson: QUERY, confirmedCount: 200 })
    );

    polls.next()();
    await flush();
    expect(getJob).toHaveBeenCalledWith({ jobId: FINISHED.recordId });
    expect(element.shadowRoot.querySelector('[data-id="job-summary"]').textContent).toBe(
      '200 matched: 200 updated, 0 unchanged, 0 failed.'
    );
    expect(element.shadowRoot.querySelector('[data-id="undo-from-tab"]')).not.toBeNull();
  });

  it('retries one failed progress read, and reports the error after a second (FINDB-19)', async () => {
    previewUpdate.mockResolvedValue({ count: 200, runLimit: 48000, objectLabel: 'Contacts' });
    startUpdate.mockResolvedValue({ ...FINISHED, status: 'Committing', running: true });
    getJob.mockRejectedValue({ body: { message: 'Connection lost' } });
    const element = await render(QUERY);
    await change(byPart(element, 'field'), 'Title');
    await change(byPart(element, 'value'), 'Coordinator');
    element.shadowRoot.querySelector('[data-id="preview"]').click();
    await flush();
    const polls = capturePolls();
    await change(element.shadowRoot.querySelector('[data-id="confirm"]'), '200');
    element.shadowRoot.querySelector('[data-id="start"]').click();
    await flush();

    polls.next()();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="error-message"]')).toBeNull();

    polls.next()();
    await flush();
    expect(getJob).toHaveBeenCalledTimes(2);
    expect(element.shadowRoot.querySelector('[data-id="error-message"]').textContent).toBe(
      'Connection lost'
    );
  });

  it('offers copy sources for the chosen field', async () => {
    getCopySources.mockResolvedValue([{ label: 'Work Email', value: 'Work_Email__c' }]);
    const element = await render(QUERY);

    await change(byPart(element, 'field'), 'Personal_Email__c');
    await change(byPart(element, 'action'), 'copy');
    await flush();

    expect(getCopySources).toHaveBeenCalledWith({
      objectName: 'Contact',
      fieldName: 'Personal_Email__c'
    });
    expect(byPart(element, 'source').options).toEqual([
      { label: 'Work Email', value: 'Work_Email__c' }
    ]);
  });

  it('changes a field with steps, sends them, and shows a record the field cannot take', async () => {
    getCopySources.mockResolvedValue([
      { label: 'Last Name', value: 'LastName' },
      { label: 'Title', value: 'Title' }
    ]);
    previewUpdate.mockResolvedValue({
      count: 2,
      runLimit: 48000,
      objectLabel: 'Contacts',
      sample: [
        {
          recordId: '003000000000001',
          name: 'Ana Ramirez',
          changes: [{ label: 'Title', before: 'volunteer', after: 'Volunteer Ramirez' }]
        },
        {
          recordId: '003000000000002',
          name: 'Ben Okafor',
          changes: [{ label: 'Title', before: 'x', problem: 'Title cannot take the value.' }]
        }
      ]
    });
    const element = await render(QUERY);

    await change(byPart(element, 'field'), 'Title');
    const actions = byPart(element, 'action').options.map((option) => option.value);
    expect(actions).toContain('transform');
    await change(byPart(element, 'action'), 'transform');
    await flush();

    const editor = element.shadowRoot.querySelector('c-import-column-transforms');
    expect(editor).not.toBeNull();
    expect(editor.embedded).toBe(true);
    expect(editor.source).toBe('Title');
    expect(editor.columnOptions).toEqual([
      { label: 'Last Name', value: 'LastName' },
      { label: 'Title', value: 'Title' }
    ]);
    const steps = [{ op: 'proper' }, { op: 'append', columns: ['LastName'] }];
    editor.dispatchEvent(
      new CustomEvent('change', { detail: { source: 'Title', transforms: steps } })
    );
    await flush();
    element.shadowRoot.querySelector('[data-id="preview"]').click();
    await flush();

    expect(previewUpdate).toHaveBeenCalledWith({
      queryJson: QUERY,
      changesJson: JSON.stringify([{ field: 'Title', action: 'transform', transforms: steps }])
    });
    const rows = element.shadowRoot.querySelectorAll('[data-id="sample-row"]');
    expect(rows).toHaveLength(2);
    expect(rows[0].textContent).toContain('Volunteer Ramirez');
    const refused = rows[1].querySelectorAll('td')[2];
    expect(refused.textContent).toBe('Title cannot take the value.');
    expect(refused.className).toContain('slds-text-color_error');
  });

  it('does not offer steps for a lookup', async () => {
    getTargets.mockResolvedValue([
      {
        apiName: 'ReportsToId',
        label: 'Reports To',
        dataType: 'reference',
        nillable: true,
        referenceTo: 'Contact',
        picklistValues: []
      }
    ]);
    const element = await render(QUERY);

    await change(byPart(element, 'field'), 'ReportsToId');

    const actions = byPart(element, 'action').options.map((option) => option.value);
    expect(actions).not.toContain('transform');
  });

  it('shows the server refusal as it is', async () => {
    previewUpdate.mockRejectedValue({ body: { message: 'No records match this query.' } });
    const element = await render(QUERY);

    await change(byPart(element, 'field'), 'Title');
    element.shadowRoot.querySelector('[data-id="preview"]').click();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error-message"]').textContent).toBe(
      'No records match this query.'
    );
  });

  it('tells Find when it is closed', async () => {
    const element = await render(QUERY);
    const closed = jest.fn();
    element.addEventListener('close', closed);

    element.shadowRoot.querySelector('[data-id="close"]').click();

    expect(closed).toHaveBeenCalledTimes(1);
  });
});
