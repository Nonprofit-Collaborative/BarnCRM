import { createElement } from 'lwc';
import FieldUtilization from 'c/fieldUtilization';
import getView from '@salesforce/apex/FieldUtilizationController.getView';
import getResults from '@salesforce/apex/FieldUtilizationController.getResults';
import saveObjects from '@salesforce/apex/FieldUtilizationController.saveObjects';
import setSchedule from '@salesforce/apex/FieldUtilizationController.setSchedule';
import runNow from '@salesforce/apex/FieldUtilizationController.runNow';

jest.mock(
  '@salesforce/apex/FieldUtilizationController.getView',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/FieldUtilizationController.getResults',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/apex/FieldUtilizationController.saveObjects',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/apex/FieldUtilizationController.setSchedule',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock('@salesforce/apex/FieldUtilizationController.runNow', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_FieldUtilization_NotScheduled',
  () => ({ default: 'The weekly count is not scheduled.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_FieldUtilization_ScheduleActive',
  () => ({ default: 'The count runs every Sunday at 4:00 AM.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_FieldUtilization_RunNowStarted',
  () => ({ default: 'The count has started.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_FieldUtilization_NeverRun',
  () => ({ default: 'Field use has not been counted yet.' }),
  { virtual: true }
);

const OPTIONS = [
  { value: 'Account', label: 'Account' },
  { value: 'Contact', label: 'Contact' }
];

const NEVER_RUN_VIEW = {
  canManage: true,
  scheduled: false,
  tracked: [],
  choosable: OPTIONS
};

const COUNTED_VIEW = {
  canManage: true,
  scheduled: true,
  nextRunAt: '2026-10-18T08:00:00.000Z',
  lastRun: '2026-10-11T08:04:00.000Z',
  lastRunSummary: 'Counted 112 fields on 2 kinds of records. 0 could not be counted.',
  tracked: ['Account'],
  choosable: OPTIONS
};

const RESULTS = {
  takenAt: '2026-10-11T08:00:00.000Z',
  previousTakenAt: '2026-10-04T08:00:00.000Z',
  rows: [
    {
      key: 'Phone|Organization',
      fieldLabel: 'Phone',
      fieldName: 'Phone',
      recordType: 'Organization',
      filled: 80,
      total: 100,
      percent: 80.0,
      change: 5.0,
      sampled: false
    },
    {
      key: 'Website|Organization',
      fieldLabel: 'Website',
      fieldName: 'Website',
      recordType: 'Organization',
      filled: 10,
      total: 100,
      percent: 10.0,
      change: null,
      sampled: false
    }
  ]
};

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

function render() {
  const element = createElement('c-field-utilization', { is: FieldUtilization });
  document.body.appendChild(element);
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-field-utilization', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('says nothing has been counted and the count is off on a new org', async () => {
    const element = render();
    getView.emit(NEVER_RUN_VIEW);
    await flush();

    expect(find(element, 'never-run').textContent).toBe('Field use has not been counted yet.');
    expect(find(element, 'schedule-message').textContent).toBe(
      'The weekly count is not scheduled.'
    );
    expect(find(element, 'results')).toBeNull();
    expect(getResults).not.toHaveBeenCalled();
  });

  it('shows the last count and the first tracked object results with their change', async () => {
    getResults.mockResolvedValue(RESULTS);
    const element = render();
    getView.emit(COUNTED_VIEW);
    await flush();

    expect(find(element, 'last-run-summary').textContent).toContain('Counted 112 fields');
    expect(getResults).toHaveBeenCalledWith({ objectName: 'Account' });
    const table = find(element, 'results');
    expect(table.data).toHaveLength(2);
    expect(table.data[0].share).toBeCloseTo(0.8);
    expect(table.data[0].change).toBe(5.0);
    expect(find(element, 'compared')).not.toBeNull();
  });

  it('sorts the least filled fields first', async () => {
    getResults.mockResolvedValue(RESULTS);
    const element = render();
    getView.emit(COUNTED_VIEW);
    await flush();

    const table = find(element, 'results');
    table.dispatchEvent(
      new CustomEvent('sort', { detail: { fieldName: 'share', sortDirection: 'asc' } })
    );
    await flush();

    expect(find(element, 'results').data[0].fieldLabel).toBe('Website');
  });

  it('saves the chosen objects', async () => {
    saveObjects.mockResolvedValue({ ...NEVER_RUN_VIEW, tracked: ['Contact'] });
    getResults.mockResolvedValue({ rows: [] });
    const element = render();
    getView.emit(NEVER_RUN_VIEW);
    await flush();

    find(element, 'objects').dispatchEvent(
      new CustomEvent('change', { detail: { value: ['Contact'] } })
    );
    find(element, 'save').click();
    await flush();

    expect(saveObjects).toHaveBeenCalledWith({ objectNames: ['Contact'] });
    expect(find(element, 'notice')).not.toBeNull();
  });

  it('schedules the weekly count and counts now', async () => {
    setSchedule.mockResolvedValue({ ...NEVER_RUN_VIEW, scheduled: true });
    runNow.mockResolvedValue({ ...NEVER_RUN_VIEW, scheduled: true });
    const element = render();
    getView.emit(NEVER_RUN_VIEW);
    await flush();

    find(element, 'schedule-button').click();
    await flush();
    expect(setSchedule).toHaveBeenCalledWith({ scheduled: true });
    expect(find(element, 'schedule-message').textContent).toBe(
      'The count runs every Sunday at 4:00 AM.'
    );

    find(element, 'run-now').click();
    await flush();
    expect(runNow).toHaveBeenCalled();
    expect(find(element, 'notice').textContent).toBe('The count has started.');
  });

  it('shows the message the server gives when a change is refused', async () => {
    runNow.mockRejectedValue({
      body: { message: 'Choose at least one kind of record to count, then save.' }
    });
    const element = render();
    getView.emit(NEVER_RUN_VIEW);
    await flush();

    find(element, 'run-now').click();
    await flush();

    expect(find(element, 'error').textContent).toContain('Choose at least one kind of record');
  });
});
