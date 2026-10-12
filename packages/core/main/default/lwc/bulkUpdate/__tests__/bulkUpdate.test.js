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
    getPage.mockResolvedValue({ runLimit: 48000, maxChanges: 5, jobs: [] });
    getTargets.mockResolvedValue(TARGETS);
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
    const start = element.shadowRoot.querySelector('[data-id="start"]');
    expect(start.disabled).toBe(true);

    let poll;
    jest.spyOn(window, 'setInterval').mockImplementation((callback) => {
      poll = callback;
      return 1;
    });
    jest.spyOn(window, 'clearInterval').mockImplementation(() => {});
    await change(element.shadowRoot.querySelector('[data-id="confirm"]'), '200');
    expect(start.disabled).toBe(false);
    start.click();
    await flush();
    expect(startUpdate).toHaveBeenCalledWith(
      expect.objectContaining({ queryJson: QUERY, confirmedCount: 200 })
    );

    poll();
    await flush();
    expect(getJob).toHaveBeenCalledWith({ jobId: FINISHED.recordId });
    expect(element.shadowRoot.querySelector('[data-id="job-summary"]').textContent).toBe(
      '200 matched: 200 updated, 0 unchanged, 0 failed.'
    );
    expect(element.shadowRoot.querySelector('[data-id="undo-from-tab"]')).not.toBeNull();
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
