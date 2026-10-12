import { createElement } from 'lwc';
import GivingNightlyJobs from 'c/givingNightlyJobs';
import getJobs from '@salesforce/apex/GivingJobsController.getJobs';
import setSchedule from '@salesforce/apex/GivingJobsController.setSchedule';
import runNow from '@salesforce/apex/GivingJobsController.runNow';

jest.mock(
  '@salesforce/apex/GivingJobsController.getJobs',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock('@salesforce/apex/GivingJobsController.setSchedule', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock('@salesforce/apex/GivingJobsController.runNow', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock('@salesforce/customPermission/Manage_BarnCRM_Settings', () => ({ default: true }), {
  virtual: true
});

jest.mock(
  '@salesforce/label/c.Giving_NightlyJobs_ScheduleActive',
  () => ({ default: 'The nightly jobs are scheduled.' }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Giving_NightlyJobs_NotScheduled',
  () => ({
    default:
      'The nightly jobs are not scheduled, so no schedule is being extended and no payment will turn Overdue on its own.'
  }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Giving_NightlyJobs_ScheduleButton',
  () => ({ default: 'Schedule the nightly jobs' }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Giving_NightlyJobs_StopButton',
  () => ({ default: 'Stop the nightly jobs' }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Giving_NightlyJobs_RunNowStarted',
  () => ({
    default:
      'The top up and the overdue pass have started. Refresh this page in a minute to see what they did.'
  }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Giving_NightlyJobs_Stale',
  () => ({ default: 'This job was due and did not record a run. Open the Error Log to see why.' }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Giving_NightlyJobs_NeverRun',
  () => ({ default: 'Has not run yet.' }),
  { virtual: true }
);

const TOP_UP = {
  name: 'Installment top up, 1:15 AM',
  description: 'Extends every active recurring commitment up to the generation horizon.',
  scheduled: true,
  lastRun: '2027-01-15T09:15:00.000Z',
  lastRunSummary: 'Extended 4 recurring schedules. 0 chunks could not be extended.',
  stale: false
};

const OVERDUE = {
  name: 'Overdue pass, 1:45 AM',
  description: 'Marks an unpaid payment Overdue once it is past the grace period.',
  scheduled: true,
  lastRun: '2027-01-15T09:45:00.000Z',
  lastRunSummary: 'No payments were overdue.',
  stale: false
};

const LEVELS = {
  name: 'Donor levels, 3:00 AM',
  description: 'Places every donor on the rung their giving now reaches.',
  scheduled: true,
  lastRun: '2027-01-15T11:00:00.000Z',
  lastRunSummary: null,
  stale: false
};

const RUNNING = {
  canManage: true,
  scheduled: true,
  nextRunAt: '2027-01-16T09:15:00.000Z',
  jobs: [TOP_UP, OVERDUE, LEVELS]
};

const NEVER_SCHEDULED = {
  canManage: true,
  scheduled: false,
  nextRunAt: null,
  jobs: [
    { ...TOP_UP, scheduled: false, lastRun: null, lastRunSummary: null },
    { ...OVERDUE, scheduled: false, lastRun: null, lastRunSummary: null },
    { ...LEVELS, scheduled: false, lastRun: null }
  ]
};

const STALE = {
  ...RUNNING,
  jobs: [TOP_UP, { ...OVERDUE, stale: true }, LEVELS]
};

function createComponent() {
  const element = createElement('c-giving-nightly-jobs', { is: GivingNightlyJobs });
  document.body.appendChild(element);
  return element;
}

function flush() {
  return Promise.resolve().then(() => Promise.resolve());
}

describe('c-giving-nightly-jobs', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists every job with when it last ran and what it did', async () => {
    const element = createComponent();
    getJobs.emit(RUNNING);
    await flush();

    const rows = element.shadowRoot.querySelectorAll('[data-id="job"]');
    expect(rows).toHaveLength(3);
    expect(element.shadowRoot.querySelectorAll('[data-id="job-name"]')[1].textContent).toBe(
      OVERDUE.name
    );
    const lastRuns = element.shadowRoot.querySelectorAll('[data-id="job-last-run"]');
    expect(lastRuns).toHaveLength(3);
    expect(lastRuns[0].value).toBe(TOP_UP.lastRun);
    const summaries = element.shadowRoot.querySelectorAll('[data-id="job-summary"]');
    // The donor level pass records a timestamp and no sentence, so two of the three have one.
    expect(summaries).toHaveLength(2);
    expect(summaries[1].textContent).toBe(OVERDUE.lastRunSummary);
  });

  it('tells an org that never switched the jobs on that they are not scheduled, without warning it about a missed run', async () => {
    const element = createComponent();
    getJobs.emit(NEVER_SCHEDULED);
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="schedule-message"]').textContent).toBe(
      'The nightly jobs are not scheduled, so no schedule is being extended and no payment will turn Overdue on its own.'
    );
    expect(element.shadowRoot.querySelector('[data-id="schedule-button"]').label).toBe(
      'Schedule the nightly jobs'
    );
    expect(element.shadowRoot.querySelector('[data-id="next-run"]')).toBeNull();
    expect(element.shadowRoot.querySelectorAll('[data-id="job-never-run"]')).toHaveLength(3);
    expect(element.shadowRoot.querySelector('[data-id="job-stale"]')).toBeNull();
  });

  it('warns about the one job that was due and recorded nothing', async () => {
    const element = createComponent();
    getJobs.emit(STALE);
    await flush();

    const warnings = element.shadowRoot.querySelectorAll('[data-id="job-stale"]');
    expect(warnings).toHaveLength(1);
    expect(warnings[0].textContent).toBe(
      'This job was due and did not record a run. Open the Error Log to see why.'
    );
  });

  it('offers Stop once the jobs are scheduled, and asks the controller to stop them', async () => {
    setSchedule.mockResolvedValue(NEVER_SCHEDULED);
    const element = createComponent();
    getJobs.emit(RUNNING);
    await flush();

    const button = element.shadowRoot.querySelector('[data-id="schedule-button"]');
    expect(button.label).toBe('Stop the nightly jobs');
    button.click();
    await flush();

    expect(setSchedule).toHaveBeenCalledWith({ scheduled: false });
  });

  it('schedules the jobs when they are not scheduled', async () => {
    setSchedule.mockResolvedValue(RUNNING);
    const element = createComponent();
    getJobs.emit(NEVER_SCHEDULED);
    await flush();

    element.shadowRoot.querySelector('[data-id="schedule-button"]').click();
    await flush();

    expect(setSchedule).toHaveBeenCalledWith({ scheduled: true });
  });

  it('says the run has started when the administrator does not want to wait for tonight', async () => {
    runNow.mockResolvedValue(RUNNING);
    const element = createComponent();
    getJobs.emit(RUNNING);
    await flush();

    element.shadowRoot.querySelector('[data-id="run-now"]').click();
    await flush();

    expect(runNow).toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('[data-id="notice"]').textContent).toBe(
      'The top up and the overdue pass have started. Refresh this page in a minute to see what they did.'
    );
  });

  it('shows the message the controller refused with rather than a stack trace', async () => {
    setSchedule.mockRejectedValue({
      body: {
        message: 'Scheduling the nightly jobs needs the Manage BarnCRM Settings permission.'
      }
    });
    const element = createComponent();
    getJobs.emit(NEVER_SCHEDULED);
    await flush();

    element.shadowRoot.querySelector('[data-id="schedule-button"]').click();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error"]').textContent).toBe(
      'Scheduling the nightly jobs needs the Manage BarnCRM Settings permission.'
    );
  });
});
