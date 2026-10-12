import { createElement } from 'lwc';
import ErrorDigestJob from 'c/errorDigestJob';
import getDigest from '@salesforce/apex/ErrorDigestController.getDigest';
import setSchedule from '@salesforce/apex/ErrorDigestController.setSchedule';
import sendNow from '@salesforce/apex/ErrorDigestController.sendNow';

jest.mock(
  '@salesforce/apex/ErrorDigestController.getDigest',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock('@salesforce/apex/ErrorDigestController.setSchedule', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock('@salesforce/apex/ErrorDigestController.sendNow', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock('@salesforce/customPermission/Manage_Nonprofit_Settings', () => ({ default: true }), {
  virtual: true
});

jest.mock(
  '@salesforce/label/c.Core_ErrorDigest_NotScheduled',
  () => ({ default: 'Not scheduled: no digest is sent.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_ErrorDigest_ScheduleActive',
  () => ({ default: 'Scheduled every morning at 7:00. Next run:' }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Core_ErrorDigest_ScheduleButton', () => ({ default: 'Schedule' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_ErrorDigest_StopButton', () => ({ default: 'Stop' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_ErrorDigest_ToAdministrators',
  () => ({ default: 'everyone with the Manage BarnCRM Settings permission:' }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Core_ErrorDigest_NoRecipients', () => ({ default: 'nobody yet.' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_ErrorDigest_UnexpectedError',
  () => ({ default: 'Something went wrong with the error digest.' }),
  { virtual: true }
);

const STOPPED = {
  canManage: true,
  scheduled: false,
  nextRunAt: null,
  lastRun: null,
  lastRunSummary: null,
  recipients: ['Maria Lopez', 'David Chen'],
  toAdministrators: true
};

const RUNNING = {
  ...STOPPED,
  scheduled: true,
  nextRunAt: '2026-09-25T07:00:00.000Z',
  lastRun: '2026-09-24T07:00:00.000Z',
  lastRunSummary: 'Sent 7 new entries to 2 people.'
};

function createComponent() {
  const element = createElement('c-error-digest-job', { is: ErrorDigestJob });
  document.body.appendChild(element);
  return element;
}

function flush() {
  return Promise.resolve().then(() => Promise.resolve());
}

function byId(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

describe('c-error-digest-job', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('says the digest is off, has never run, and who it would go to', async () => {
    const element = createComponent();
    getDigest.emit(STOPPED);
    await flush();

    expect(byId(element, 'schedule-message').textContent).toContain('Not scheduled');
    expect(byId(element, 'next-run')).toBeNull();
    expect(byId(element, 'never-run')).not.toBeNull();
    expect(byId(element, 'recipients').textContent).toContain(
      'everyone with the Manage BarnCRM Settings permission: Maria Lopez, David Chen'
    );
    expect(byId(element, 'schedule-button').label).toBe('Schedule');
    expect(byId(element, 'read-only')).toBeNull();
  });

  it('shows the next run, the last run and what it did while scheduled', async () => {
    const element = createComponent();
    getDigest.emit(RUNNING);
    await flush();

    expect(byId(element, 'schedule-message').textContent).toContain('Scheduled every morning');
    expect(byId(element, 'next-run')).not.toBeNull();
    expect(byId(element, 'last-run')).not.toBeNull();
    expect(byId(element, 'last-run-summary').textContent).toContain('Sent 7 new entries');
    expect(byId(element, 'schedule-button').label).toBe('Stop');
  });

  it('names the listed people without the administrators wording', async () => {
    const element = createComponent();
    getDigest.emit({ ...STOPPED, recipients: ['Jen Park'], toAdministrators: false });
    await flush();

    const text = byId(element, 'recipients').textContent;
    expect(text).toContain('Jen Park');
    expect(text).not.toContain('everyone with');
  });

  it('says when nobody would receive it', async () => {
    const element = createComponent();
    getDigest.emit({ ...STOPPED, recipients: [] });
    await flush();

    expect(byId(element, 'recipients').textContent).toContain('nobody yet.');
  });

  it('schedules the digest and shows the page the server returns', async () => {
    setSchedule.mockResolvedValue(RUNNING);
    const element = createComponent();
    getDigest.emit(STOPPED);
    await flush();

    byId(element, 'schedule-button').click();
    await flush();

    expect(setSchedule).toHaveBeenCalledWith({ scheduled: true });
    expect(byId(element, 'schedule-button').label).toBe('Stop');
  });

  it('stops a scheduled digest', async () => {
    setSchedule.mockResolvedValue(STOPPED);
    const element = createComponent();
    getDigest.emit(RUNNING);
    await flush();

    byId(element, 'schedule-button').click();
    await flush();

    expect(setSchedule).toHaveBeenCalledWith({ scheduled: false });
  });

  it('sends one now and shows what the run did', async () => {
    sendNow.mockResolvedValue({
      ...RUNNING,
      lastRunSummary: 'Nothing new since Sep 23, 7:00 AM: no email sent.'
    });
    const element = createComponent();
    getDigest.emit(RUNNING);
    await flush();

    byId(element, 'send-now').click();
    await flush();

    expect(sendNow).toHaveBeenCalled();
    expect(byId(element, 'last-run-summary').textContent).toContain('Nothing new');
  });

  it('shows the message the server refused with', async () => {
    sendNow.mockRejectedValue({
      body: { message: 'Needs the Manage BarnCRM Settings permission.' }
    });
    const element = createComponent();
    getDigest.emit(RUNNING);
    await flush();

    byId(element, 'send-now').click();
    await flush();

    expect(byId(element, 'error').textContent).toContain('Manage BarnCRM Settings');
  });

  it('shows the message the page could not load with', async () => {
    const element = createComponent();
    getDigest.error({ message: 'Something went wrong with the error digest.' });
    await flush();

    expect(byId(element, 'error').textContent).toContain('Something went wrong');
  });
});
