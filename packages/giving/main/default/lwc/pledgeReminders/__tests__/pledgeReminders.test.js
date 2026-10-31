import { createElement } from 'lwc';
import PledgeReminders from 'c/pledgeReminders';
import getPage from '@salesforce/apex/PledgeReminderController.getPage';
import sendNow from '@salesforce/apex/PledgeReminderController.sendNow';
import produceLetters from '@salesforce/apex/PledgeReminderController.produceLetters';
import markLettersSent from '@salesforce/apex/PledgeReminderController.markLettersSent';

jest.mock(
  '@salesforce/apex/PledgeReminderController.getPage',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock('@salesforce/apex/PledgeReminderController.sendNow', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/PledgeReminderController.produceLetters',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/PledgeReminderController.markLettersSent',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/PledgeReminderController.setSchedule', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex', () => ({ refreshApex: jest.fn(() => Promise.resolve()) }), {
  virtual: true
});

jest.mock(
  '@salesforce/label/c.Giving_PledgeReminders_Off',
  () => ({ default: 'Reminders are off' }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/label/c.Giving_PledgeReminders_TemplateMissing',
  () => ({ default: 'Template not found' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Giving_PledgeReminders_DaysBefore',
  () => ({ default: '{0} days before' }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/label/c.Giving_PledgeReminders_DaysAfter',
  () => ({ default: '{0} days after' }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/label/c.Giving_PledgeReminders_OnDueDate',
  () => ({ default: 'On the due date' }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/label/c.Giving_PledgeReminders_SendStarted',
  () => ({ default: 'The run has started.' }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Giving_PledgeReminders_Inactive', () => ({ default: 'Inactive' }), {
  virtual: true
});

const flush = () => Promise.resolve().then(() => Promise.resolve());

function pageData(overrides = {}) {
  return {
    enabled: true,
    canManage: true,
    canSend: true,
    scheduled: false,
    nextRunAt: null,
    lastRun: null,
    lastRunSummary: null,
    emailsDue: 2,
    lettersDue: 1,
    withoutRecipient: 0,
    lettersWaiting: 0,
    lettersAwaitingConfirmation: 0,
    lettersFileId: null,
    steps: [
      {
        id: 'a1',
        name: 'Week ahead',
        days: -7,
        channel: 'Email',
        template: 'Pledge_Soon',
        templateLabel: 'Pledge Soon',
        templateFound: true,
        active: true
      },
      {
        id: 'a2',
        name: 'Final letter',
        days: 30,
        channel: 'Letter',
        template: null,
        templateLabel: null,
        templateFound: true,
        active: false
      },
      {
        id: 'a3',
        name: 'Broken',
        days: 0,
        channel: 'Email',
        template: 'Gone',
        templateLabel: null,
        templateFound: false,
        active: true
      }
    ],
    templates: [{ label: 'Pledge Soon', developerName: 'Pledge_Soon' }],
    reminders: [],
    ...overrides
  };
}

async function mount(data) {
  const element = createElement('c-pledge-reminders', { is: PledgeReminders });
  document.body.appendChild(element);
  getPage.emit(data);
  await flush();
  return element;
}

const q = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

afterEach(() => {
  while (document.body.firstChild) {
    document.body.removeChild(document.body.firstChild);
  }
  jest.clearAllMocks();
});

describe('c-pledge-reminders', () => {
  it('shows the steps with their timing, and a missing template as an error', async () => {
    const element = await mount(pageData());
    const timings = [...element.shadowRoot.querySelectorAll('[data-id="step-timing"]')].map(
      (cell) => cell.textContent
    );
    expect(timings).toEqual(['7 days before', '30 days after', 'On the due date']);
    expect(q(element, 'template-missing').textContent).toContain('Template not found');
    expect(q(element, 'template-name').textContent).toBe('Pledge Soon');
    expect(element.shadowRoot.querySelectorAll('[data-id="step-active"]')[1].textContent).toBe(
      'Inactive'
    );
  });

  it('says reminders are off and refuses to send while they are', async () => {
    const element = await mount(pageData({ enabled: false }));
    expect(q(element, 'off-notice').textContent).toContain('Reminders are off');
    expect(q(element, 'send-now').disabled).toBe(true);
  });

  it('sends now when on and something is due', async () => {
    sendNow.mockResolvedValue(pageData());
    const element = await mount(pageData());
    expect(q(element, 'off-notice')).toBeNull();
    expect(q(element, 'emails-due').textContent).toBe('2');
    q(element, 'send-now').click();
    await flush();
    await flush();
    expect(sendNow).toHaveBeenCalledTimes(1);
    expect(q(element, 'notice-message').textContent).toBe('The run has started.');
  });

  it('disables sending for a person without the permission', async () => {
    const element = await mount(pageData({ canSend: false }));
    expect(q(element, 'send-now').disabled).toBe(true);
    expect(q(element, 'produce-letters').disabled).toBe(true);
  });

  it('produces the letter file and marks letters sent', async () => {
    produceLetters.mockResolvedValue(
      pageData({ lettersWaiting: 0, lettersAwaitingConfirmation: 3, lettersFileId: '069xx' })
    );
    markLettersSent.mockResolvedValue(pageData());
    const element = await mount(pageData({ lettersWaiting: 3 }));
    expect(q(element, 'produce-letters').disabled).toBe(false);
    expect(q(element, 'mark-sent').disabled).toBe(true);
    q(element, 'produce-letters').click();
    await flush();
    await flush();
    expect(produceLetters).toHaveBeenCalledTimes(1);
    expect(q(element, 'letters-file').href).toContain(
      '/sfc/servlet.shepherd/document/download/069xx'
    );
    expect(q(element, 'mark-sent').disabled).toBe(false);
    q(element, 'mark-sent').click();
    await flush();
    expect(markLettersSent).toHaveBeenCalledTimes(1);
  });

  it('shows an error returned by an action', async () => {
    sendNow.mockRejectedValue({ body: { message: 'Pledge reminders are turned off.' } });
    const element = await mount(pageData());
    q(element, 'send-now').click();
    await flush();
    await flush();
    expect(q(element, 'error-message').textContent).toBe('Pledge reminders are turned off.');
  });
});
