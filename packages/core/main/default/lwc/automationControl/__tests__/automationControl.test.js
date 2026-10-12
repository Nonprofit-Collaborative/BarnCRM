import { createElement } from 'lwc';
import AutomationControl from 'c/automationControl';
import getPage from '@salesforce/apex/AutomationControlController.getPage';
import pauseAll from '@salesforce/apex/AutomationControlController.pauseAll';
import resumeAll from '@salesforce/apex/AutomationControlController.resumeAll';
import setEnabled from '@salesforce/apex/AutomationControlController.setEnabled';

jest.mock(
  '@salesforce/apex/AutomationControlController.getPage',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock('@salesforce/apex/AutomationControlController.pauseAll', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock(
  '@salesforce/apex/AutomationControlController.resumeAll',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/AutomationControlController.setEnabled',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock('@salesforce/customPermission/Manage_BarnCRM_Settings', () => ({ default: true }), {
  virtual: true
});

jest.mock(
  '@salesforce/label/c.Core_AutomationControl_PausedBanner',
  () => ({ default: 'Automation is paused until' }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Core_AutomationControl_PausedBy',
  () => ({ default: 'Paused by {0}.' }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Core_AutomationControl_ResumesItself',
  () => ({ default: 'It turns itself back on then.' }),
  { virtual: true }
);

const RUNNING_PAGE = {
  paused: false,
  pausedUntil: null,
  canManage: true,
  pauseHourOptions: [1, 2, 4, 8, 24],
  automations: [
    {
      recordId: '001000000000000AAA',
      automationName: 'Household_Naming',
      label: 'Household naming',
      description: 'Keeps household names and greetings up to date.',
      objectName: 'Contact',
      enabled: true
    }
  ]
};

const ALWAYS_RUNS_PAGE = {
  ...RUNNING_PAGE,
  automations: [
    RUNNING_PAGE.automations[0],
    {
      recordId: '001000000000001AAA',
      automationName: 'Gift_Receipt_Lock',
      label: 'Gift: receipt lock',
      description: 'Protects the receipt a donor is holding.',
      objectName: 'Gift__c',
      enabled: false,
      alwaysRuns: true
    }
  ]
};

const PAUSED_PAGE = {
  ...RUNNING_PAGE,
  paused: true,
  pausedUntil: '2026-09-07T15:40:00.000Z'
};

function createComponent() {
  const element = createElement('c-automation-control', { is: AutomationControl });
  document.body.appendChild(element);
  return element;
}

function flush() {
  return Promise.resolve().then(() => Promise.resolve());
}

describe('c-automation-control', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists every automation Maria can switch', async () => {
    const element = createComponent();
    getPage.emit(RUNNING_PAGE);
    await flush();

    const toggles = element.shadowRoot.querySelectorAll('.automation-toggle');
    expect(toggles.length).toBe(1);
    expect(toggles[0].checked).toBe(true);
    expect(toggles[0].disabled).toBe(false);
    expect(element.shadowRoot.querySelector('[data-id="paused-banner"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="empty-state"]')).toBeNull();
  });

  it('shows an automation that always runs as off, disabled, and says why', async () => {
    const element = createComponent();
    getPage.emit(ALWAYS_RUNS_PAGE);
    await flush();

    const toggles = element.shadowRoot.querySelectorAll('.automation-toggle');
    expect(toggles.length).toBe(2);
    // The ordinary automation is unaffected: it is the row, not the page, that is not switchable.
    expect(toggles[0].disabled).toBe(false);
    expect(toggles[1].disabled).toBe(true);
    expect(toggles[1].checked).toBe(false);

    const reasons = element.shadowRoot.querySelectorAll('[data-id="always-runs-reason"]');
    expect(reasons.length).toBe(1);
    expect(reasons[0].textContent.trim().length).toBeGreaterThan(0);
  });

  it('never asks the server to switch an automation that always runs', async () => {
    const element = createComponent();
    getPage.emit(ALWAYS_RUNS_PAGE);
    await flush();

    const toggle = element.shadowRoot.querySelectorAll('.automation-toggle')[1];
    toggle.checked = true;
    toggle.dispatchEvent(new CustomEvent('change'));
    await flush();

    expect(setEnabled).not.toHaveBeenCalled();
    expect(element.shadowRoot.querySelectorAll('.automation-toggle')[1].checked).toBe(false);
  });

  it('shows the banner while automation is paused, and announces it', async () => {
    const element = createComponent();
    getPage.emit(PAUSED_PAGE);
    await flush();

    const banner = element.shadowRoot.querySelector('[data-id="paused-banner"]');
    expect(banner).not.toBeNull();
    expect(banner.textContent).toContain('Automation is paused until');
    // The state must not be carried by color alone (plan Section 4.14).
    const region = element.shadowRoot.querySelector('[role="status"]');
    expect(region).not.toBeNull();
    expect(region.getAttribute('aria-live')).toBe('polite');
    expect(banner.querySelector('lightning-icon')).not.toBeNull();
  });

  it('names who paused and says the pause ends by itself', async () => {
    const element = createComponent();
    getPage.emit({ ...PAUSED_PAGE, pausedBy: 'Maria Lopez' });
    await flush();

    const pausedBy = element.shadowRoot.querySelector('[data-id="paused-by"]');
    expect(pausedBy).not.toBeNull();
    expect(pausedBy.textContent).toBe('Paused by Maria Lopez.');
    const detail = element.shadowRoot.querySelector('[data-id="paused-detail"]');
    expect(detail.textContent).toContain('It turns itself back on then.');
  });

  it('leaves the name out when nobody is on record as pausing', async () => {
    const element = createComponent();
    getPage.emit(PAUSED_PAGE);
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="paused-by"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="paused-detail"]').textContent).toContain(
      'It turns itself back on then.'
    );
  });

  it('offers the five pause lengths and pauses for the one chosen', async () => {
    pauseAll.mockResolvedValue(PAUSED_PAGE);
    const element = createComponent();
    getPage.emit(RUNNING_PAGE);
    await flush();

    const hours = element.shadowRoot.querySelector('[data-id="pause-hours"]');
    expect(hours.options.map((option) => option.value)).toEqual(['1', '2', '4', '8', '24']);

    hours.dispatchEvent(new CustomEvent('change', { detail: { value: '4' } }));
    element.shadowRoot.querySelector('[data-id="pause-button"]').click();
    await flush();

    expect(pauseAll).toHaveBeenCalledWith({ hours: 4 });
    expect(element.shadowRoot.querySelector('[data-id="paused-banner"]')).not.toBeNull();
  });

  it('resumes automation', async () => {
    resumeAll.mockResolvedValue(RUNNING_PAGE);
    const element = createComponent();
    getPage.emit(PAUSED_PAGE);
    await flush();

    element.shadowRoot.querySelector('[data-id="resume-button"]').click();
    await flush();

    expect(resumeAll).toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('[data-id="paused-banner"]')).toBeNull();
  });

  it('switches one automation off', async () => {
    setEnabled.mockResolvedValue({
      ...RUNNING_PAGE,
      automations: [{ ...RUNNING_PAGE.automations[0], enabled: false }]
    });
    const element = createComponent();
    getPage.emit(RUNNING_PAGE);
    await flush();

    const toggle = element.shadowRoot.querySelector('.automation-toggle');
    toggle.checked = false;
    toggle.dispatchEvent(new CustomEvent('change'));
    await flush();

    expect(setEnabled).toHaveBeenCalledWith({
      automationName: 'Household_Naming',
      enabled: false
    });
  });

  it('puts the switch back where it was when the server refuses the change', async () => {
    setEnabled.mockRejectedValue({
      body: { message: 'Ask an administrator to make this change.' }
    });
    const element = createComponent();
    getPage.emit(RUNNING_PAGE);
    await flush();

    const toggle = element.shadowRoot.querySelector('.automation-toggle');
    expect(toggle.checked).toBe(true);
    toggle.checked = false;
    toggle.dispatchEvent(new CustomEvent('change'));
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error-message"]').textContent).toBe(
      'Ask an administrator to make this change.'
    );
    expect(element.shadowRoot.querySelector('.automation-toggle').checked).toBe(true);
  });

  it('shows the message the server sends when something is refused', async () => {
    pauseAll.mockRejectedValue({ body: { message: 'Choose how long to pause automation.' } });
    const element = createComponent();
    getPage.emit(RUNNING_PAGE);
    await flush();

    element.shadowRoot.querySelector('[data-id="pause-button"]').click();
    await flush();

    const error = element.shadowRoot.querySelector('[data-id="error-message"]');
    expect(error.textContent).toBe('Choose how long to pause automation.');
    expect(element.shadowRoot.querySelector('[role="alert"]')).not.toBeNull();
  });

  it('says so when the page has nothing to list', async () => {
    const element = createComponent();
    getPage.emit({ ...RUNNING_PAGE, automations: [] });
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="empty-state"]')).not.toBeNull();
  });

  it('reports a failure to load the page', async () => {
    const element = createComponent();
    getPage.error({ message: 'You do not have access to this page.' });
    await flush();

    const error = element.shadowRoot.querySelector('[data-id="error-message"]');
    expect(error.textContent).toBe('You do not have access to this page.');
  });
});
