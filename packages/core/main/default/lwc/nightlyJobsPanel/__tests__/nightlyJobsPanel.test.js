import { createElement } from 'lwc';
import NightlyJobsPanel, { timeOfDay } from 'c/nightlyJobsPanel';
import getPanel from '@salesforce/apex/NightlyJobsController.getPanel';
import schedule from '@salesforce/apex/NightlyJobsController.schedule';
import setStep from '@salesforce/apex/NightlyJobsController.setStep';
import runStep from '@salesforce/apex/NightlyJobsController.runStep';
import { setHelpTextForTest } from 'c/barnHelpText';
import { expectAccessible } from 'barn/a11y';

setHelpTextForTest({ Core_NightlyJobs_RowAction: '{0}: {1}' });

jest.mock('@salesforce/apex/NightlyJobsController.setStep', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/NightlyJobsController.runStep', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/i18n/locale', () => ({ default: 'en-US' }), { virtual: true });
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
      outcomeStatus: 'done',
      message: null
    }
  ]
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
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
    const element = await render({ ...PANEL, scheduled: true });
    const rows = element.shadowRoot.querySelectorAll('tbody tr');
    expect(rows.length).toBe(2);
    expect(rows[0].dataset.key).toBe('BarnCRM Seasonal Addresses');
    const off = rows[0].querySelector('[data-id="state"] c-barn-status-badge');
    const on = rows[1].querySelector('[data-id="state"] c-barn-status-badge');
    expect(off.label).toBe('c.Core_Feature_Off');
    expect(off.status).toBe('off');
    expect(on.label).toBe('c.Core_Feature_On');
    expect(on.status).toBe('on');
    const outcome = rows[1].querySelector('[data-id="outcome"] c-barn-status-badge');
    expect(outcome.label).toBe('Done');
    expect(outcome.status).toBe('done');
    expect(rows[0].querySelector('[data-id="outcome"] c-barn-status-badge')).toBeNull();
  });

  it('shows a step that is on as Not Scheduled while the nightly run is not scheduled', async () => {
    const element = await render();
    const rows = element.shadowRoot.querySelectorAll('tbody tr');
    const off = rows[0].querySelector('[data-id="state"] c-barn-status-badge');
    const pending = rows[1].querySelector('[data-id="state"] c-barn-status-badge');
    expect(off.label).toBe('c.Core_Feature_Off');
    expect(pending.label).toBe('c.Core_NightlyJobs_StateNotScheduled');
    expect(pending.status).toBe('warning');
  });

  it('switches a step with a switch and starts one that allows it, from its row', async () => {
    const giving = {
      key: 'BarnCRM Giving Installment Top Up',
      label: 'Installment top up',
      minute: 75,
      isOn: true,
      hasSwitch: true,
      switchedOn: true,
      canRunNow: true,
      summary: '3 payments added',
      missed: true
    };
    const element = await render({ ...PANEL, scheduled: true, steps: [PANEL.steps[0], giving] });
    const rows = element.shadowRoot.querySelectorAll('tbody tr');
    expect(rows[0].querySelector('[data-id="switch"]')).toBeNull();
    expect(rows[0].querySelector('[data-id="run-now"]')).toBeNull();
    expect(rows[1].querySelector('[data-id="summary"]').textContent).toBe('3 payments added');
    expect(rows[1].querySelector('[data-id="missed"]').label).toBe('c.Core_NightlyJobs_Missed');

    const turnOff = rows[1].querySelector('[data-id="switch"]');
    expect(turnOff.label).toBe('c.Core_NightlyJobs_TurnOff');
    // Each row's buttons name the job they act on, for a screen reader.
    expect(turnOff.title).toBe('c.Core_NightlyJobs_TurnOff: Installment top up');
    expect(rows[1].querySelector('[data-id="run-now"]').title).toBe(
      'c.Core_NightlyJobs_RunNow: Installment top up'
    );
    await expectAccessible(element);
    setStep.mockResolvedValue({
      ...PANEL,
      scheduled: true,
      steps: [PANEL.steps[0], { ...giving, isOn: false, switchedOn: false, missed: false }]
    });
    turnOff.click();
    await flush();
    expect(setStep).toHaveBeenCalledWith({ key: giving.key, turnOn: false });
    expect(element.shadowRoot.querySelector('[data-id="notice"]').message).toContain(
      'c.Core_NightlyJobs_SwitchSaved'
    );
    const turnOn = element.shadowRoot.querySelectorAll('tbody tr')[1];
    expect(turnOn.querySelector('[data-id="switch"]').label).toBe('c.Core_NightlyJobs_TurnOn');

    runStep.mockResolvedValue({ ...PANEL, scheduled: true, steps: [giving] });
    turnOn.querySelector('[data-id="run-now"]').click();
    await flush();
    expect(runStep).toHaveBeenCalledWith({ key: giving.key });
    expect(element.shadowRoot.querySelector('[data-id="notice"]').message).toContain(
      'c.Core_NightlyJobs_RunStarted'
    );
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
    expect(element.shadowRoot.querySelector('[data-id="notice"]').message).toContain(
      'c.Core_NightlyJobs_ScheduledNotice'
    );
    expect(element.shadowRoot.querySelector('[data-id="schedule"]')).toBeNull();
  });

  it('shows the error when the panel cannot load', async () => {
    getPanel.mockRejectedValue({ body: { message: 'Nope' } });
    const element = createElement('c-nightly-jobs-panel', { is: NightlyJobsPanel });
    document.body.appendChild(element);
    await flush();
    const notice = element.shadowRoot.querySelector('[data-id="error"]');
    expect(notice.variant).toBe('error');
    expect(notice.message).toContain('Nope');
  });

  it('writes minutes after midnight as a time of day', () => {
    expect(timeOfDay(75)).toMatch(/1:15/);
    expect(timeOfDay(0)).toMatch(/12:00|0:00/);
  });
});
