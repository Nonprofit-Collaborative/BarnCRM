import { createElement } from 'lwc';
import SeasonalAddressJob from 'c/seasonalAddressJob';
import getSwap from '@salesforce/apex/SeasonalAddressController.getSwap';
import runNow from '@salesforce/apex/SeasonalAddressController.runNow';
import { refreshApex } from '@salesforce/apex';

jest.mock(
  '@salesforce/apex/SeasonalAddressController.getSwap',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock('@salesforce/apex/SeasonalAddressController.runNow', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock('@salesforce/apex', () => ({ refreshApex: jest.fn(() => Promise.resolve()) }), {
  virtual: true
});

jest.mock('@salesforce/customPermission/Manage_BarnCRM_Settings', () => ({ default: true }), {
  virtual: true
});

jest.mock(
  '@salesforce/label/c.Core_SeasonalAddress_ScheduleActive',
  () => ({ default: 'The swap runs every night at 12:30 AM.' }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Core_SeasonalAddress_NotScheduled',
  () => ({
    default: 'The nightly swap is not scheduled, so seasonal addresses will not move on their own.'
  }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Core_SeasonalAddress_SwitchedOff',
  () => ({
    default: 'Seasonal Addresses is off, so seasonal addresses will not move on their own.'
  }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Core_SeasonalAddress_RunNowStarted',
  () => ({ default: 'The swap has started. Refresh this page in a minute to see what it did.' }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Core_SeasonalAddress_Stale',
  () => ({ default: 'The swap is scheduled but has not run in more than 36 hours.' }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Core_SeasonalAddress_NeverRun',
  () => ({ default: 'The seasonal address swap has not run yet.' }),
  { virtual: true }
);

const RAN_LAST_NIGHT = {
  canManage: true,
  enabled: true,
  scheduled: true,
  nextRunAt: '2027-01-16T06:30:00.000Z',
  lastRun: '2027-01-15T06:30:00.000Z',
  lastRunSummary: '3 moved to a seasonal address, 1 moved back, 0 could not be changed.',
  stale: false
};

const NEVER_RUN = {
  canManage: true,
  enabled: false,
  scheduled: false,
  nextRunAt: null,
  lastRun: null,
  lastRunSummary: null,
  stale: false
};

const OVERDUE = { ...RAN_LAST_NIGHT, stale: true };

function createComponent() {
  const element = createElement('c-seasonal-address-job', { is: SeasonalAddressJob });
  document.body.appendChild(element);
  return element;
}

function flush() {
  return Promise.resolve().then(() => Promise.resolve());
}

describe('c-seasonal-address-job', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows when the swap last ran and what it did', async () => {
    const element = createComponent();
    getSwap.emit(RAN_LAST_NIGHT);
    await flush();

    const lastRun = element.shadowRoot.querySelector('[data-id="last-run"]');
    expect(lastRun).not.toBeNull();
    expect(lastRun.value).toBe(RAN_LAST_NIGHT.lastRun);
    expect(element.shadowRoot.querySelector('[data-id="last-run-summary"]').textContent).toBe(
      RAN_LAST_NIGHT.lastRunSummary
    );
    expect(element.shadowRoot.querySelector('[data-id="never-run"]')).toBeNull();
  });

  it('says the job has never run rather than showing an empty date', async () => {
    const element = createComponent();
    getSwap.emit(NEVER_RUN);
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="last-run"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="never-run"]').textContent).toBe(
      'The seasonal address swap has not run yet.'
    );
  });

  it('says Seasonal Addresses is off and points to the switch', async () => {
    const element = createComponent();
    getSwap.emit(NEVER_RUN);
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="schedule-message"]').textContent).toBe(
      'Seasonal Addresses is off, so seasonal addresses will not move on their own.'
    );
    expect(element.shadowRoot.querySelector('[data-id="next-run"]')).toBeNull();
  });

  it('says the swap is not scheduled when the switch is on but the job is missing', async () => {
    const element = createComponent();
    getSwap.emit({ ...NEVER_RUN, enabled: true });
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="schedule-message"]').textContent).toBe(
      'The nightly swap is not scheduled, so seasonal addresses will not move on their own.'
    );
  });

  it('has no schedule or stop button, since the switch schedules the job', async () => {
    const element = createComponent();
    getSwap.emit(RAN_LAST_NIGHT);
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="schedule-button"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="run-now"]')).not.toBeNull();
  });

  it('says when the next run is due once the swap is scheduled', async () => {
    const element = createComponent();
    getSwap.emit(RAN_LAST_NIGHT);
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="schedule-message"]').textContent).toBe(
      'The swap runs every night at 12:30 AM.'
    );
    expect(
      element.shadowRoot.querySelector('[data-id="next-run"] lightning-formatted-date-time').value
    ).toBe(RAN_LAST_NIGHT.nextRunAt);
  });

  it('warns when a scheduled swap has missed its window', async () => {
    const element = createComponent();
    getSwap.emit(OVERDUE);
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="stale-warning"]').textContent).toBe(
      'The swap is scheduled but has not run in more than 36 hours.'
    );
  });

  // The settings console calls refresh() after a save, so saving the Seasonal Addresses switch
  // updates the status line without reloading the page.
  it('re-reads the swap when the console asks it to refresh', async () => {
    const element = createComponent();
    getSwap.emit(NEVER_RUN);
    await flush();
    expect(refreshApex).not.toHaveBeenCalled();

    await element.refresh();
    expect(refreshApex).toHaveBeenCalledTimes(1);

    getSwap.emit(RAN_LAST_NIGHT);
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="schedule-message"]').textContent).toBe(
      'The swap runs every night at 12:30 AM.'
    );
  });

  it('runs the swap now and says it has started', async () => {
    runNow.mockResolvedValue(RAN_LAST_NIGHT);
    const element = createComponent();
    getSwap.emit(RAN_LAST_NIGHT);
    await flush();

    element.shadowRoot.querySelector('[data-id="run-now"]').click();
    await flush();

    expect(runNow).toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('[data-id="notice"]').textContent).toBe(
      'The swap has started. Refresh this page in a minute to see what it did.'
    );
  });
});
