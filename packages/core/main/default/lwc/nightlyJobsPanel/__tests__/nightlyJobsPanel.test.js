import { createElement } from 'lwc';
import NightlyJobsPanel, { timeOfDay } from 'c/nightlyJobsPanel';
import getPanel from '@salesforce/apex/NightlyJobsController.getPanel';
import schedule from '@salesforce/apex/NightlyJobsController.schedule';

jest.mock('@salesforce/apex/NightlyJobsController.getPanel', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/NightlyJobsController.schedule', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/customPermission/Manage_BarnCRM_Settings', () => ({ default: true }), {
  virtual: true
});

const PANEL = {
  canManage: true,
  scheduled: false,
  lastRunStarted: null,
  steps: [
    { key: 'BarnCRM Seasonal Addresses', label: 'Seasonal addresses', minute: 30, isOn: false },
    {
      key: 'BarnCRM Import Row Cleanup',
      label: 'Import row cleanup',
      minute: 75,
      isOn: true,
      lastStarted: '2026-11-04T06:15:00.000Z',
      outcome: 'Done',
      message: null
    }
  ]
};

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function render(panel = PANEL) {
  getPanel.mockResolvedValue(panel);
  const element = createElement('c-nightly-jobs-panel', { is: NightlyJobsPanel });
  document.body.appendChild(element);
  await flush();
  return element;
}

describe('c-nightly-jobs-panel', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists every step in order with its time and whether it is on', async () => {
    const element = await render();
    const rows = element.shadowRoot.querySelectorAll('tbody tr');
    expect(rows.length).toBe(2);
    expect(rows[0].dataset.key).toBe('BarnCRM Seasonal Addresses');
    expect(rows[0].querySelector('[data-id="state"]').textContent).toBe('c.Core_Feature_Off');
    expect(rows[1].querySelector('[data-id="state"]').textContent).toBe('c.Core_Feature_On');
    expect(rows[1].querySelector('[data-id="outcome"]').textContent).toContain('Done');
  });

  it('says the run is not scheduled and offers to schedule it', async () => {
    const element = await render();
    expect(element.shadowRoot.querySelector('[data-id="schedule-message"]').textContent).toBe(
      'c.Core_NightlyJobs_NotScheduled'
    );
    schedule.mockResolvedValue({ ...PANEL, scheduled: true });
    element.shadowRoot.querySelector('[data-id="schedule"]').click();
    await flush();
    expect(schedule).toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('[data-id="notice"]').textContent).toContain(
      'c.Core_NightlyJobs_ScheduledNotice'
    );
    expect(element.shadowRoot.querySelector('[data-id="schedule"]')).toBeNull();
  });

  it('shows the error when the panel cannot load', async () => {
    getPanel.mockRejectedValue({ body: { message: 'Nope' } });
    const element = createElement('c-nightly-jobs-panel', { is: NightlyJobsPanel });
    document.body.appendChild(element);
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="error"]').textContent).toContain('Nope');
  });

  it('writes minutes after midnight as a time of day', () => {
    expect(timeOfDay(75)).toMatch(/1:15/);
    expect(timeOfDay(0)).toMatch(/12:00|0:00/);
  });
});
