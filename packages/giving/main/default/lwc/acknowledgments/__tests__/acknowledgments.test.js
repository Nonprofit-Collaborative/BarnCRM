import { createElement } from 'lwc';
import Acknowledgments from 'c/acknowledgments';
import getPage from '@salesforce/apex/AcknowledgmentController.getPage';
import sendEmailsNow from '@salesforce/apex/AcknowledgmentController.sendEmailsNow';
import produceLetters from '@salesforce/apex/AcknowledgmentController.produceLetters';
import markLettersSent from '@salesforce/apex/AcknowledgmentController.markLettersSent';

jest.mock(
  '@salesforce/apex/AcknowledgmentController.getPage',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/AcknowledgmentController.sendEmailsNow',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/AcknowledgmentController.produceLetters',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/AcknowledgmentController.markLettersSent',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock('@salesforce/apex/AcknowledgmentController.setSchedule', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock('@salesforce/apex', () => ({ refreshApex: jest.fn(() => Promise.resolve()) }), {
  virtual: true
});

jest.mock(
  '@salesforce/label/c.Giving_Acknowledgments_TemplateNotFound',
  () => ({ default: 'Template not found' }),
  { virtual: true }
);

jest.mock('@salesforce/label/c.Giving_Acknowledgments_Inactive', () => ({ default: 'Inactive' }), {
  virtual: true
});

jest.mock(
  '@salesforce/label/c.Giving_Acknowledgments_Off',
  () => ({
    default:
      'Acknowledging gifts is switched off, so nothing is joining the queue. Turn on Acknowledge gifts in BarnCRM Settings, under Giving.'
  }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Giving_Acknowledgments_NeverRun',
  () => ({ default: 'Nothing has been sent yet.' }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Giving_Acknowledgments_NotScheduled',
  () => ({ default: 'Not scheduled. Nothing goes out until you press Send.' }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Giving_Acknowledgments_EmailsStarted',
  () => ({ default: 'The email send has started. The run below shows how it goes.' }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Giving_Acknowledgments_LettersReady',
  () => ({
    default:
      'The letter file is ready on the run below. Merge it, print it, and then choose Mark as sent.'
  }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Giving_Acknowledgments_LettersMarkedSent',
  () => ({ default: 'Those letters are recorded as sent.' }),
  { virtual: true }
);

jest.mock('@salesforce/label/c.Giving_Acknowledgments_AnyAmount', () => ({ default: 'Any gift' }), {
  virtual: true
});

const PAGE = {
  enabled: true,
  canManage: true,
  canSend: true,
  scheduled: false,
  nextRunAt: null,
  lastRun: '2026-09-08T09:45:00.000Z',
  lastRunSummary: 'Emailed thank yous: 12 sent, 0 did not go.',
  emailQueue: 4,
  letterQueue: 2,
  unmatchedQueue: 1,
  withoutRecipient: 3,
  queueCapped: false,
  rules: [
    {
      id: 'a06000000000001AAA',
      name: 'Major gifts',
      order: 10,
      channel: 'Letter',
      template: null,
      templateFound: true,
      minimumAmount: 1000,
      maximumAmount: null,
      giftType: null,
      appealName: null,
      firstGiftOnly: false,
      active: true
    },
    {
      id: 'a06000000000002AAA',
      name: 'Everything else',
      order: 100,
      channel: 'Email',
      template: 'BarnCRM_Thank_You',
      templateFound: false,
      minimumAmount: null,
      maximumAmount: null,
      giftType: null,
      appealName: null,
      firstGiftOnly: false,
      active: false
    }
  ],
  templates: [{ label: 'BarnCRM: thank you for your gift', developerName: 'BarnCRM_Thank_You' }],
  runs: [
    {
      id: 'a07000000000001AAA',
      name: 'AR-000001',
      channel: 'Letter',
      status: 'Ready to merge',
      started: '2026-09-09T10:00:00.000Z',
      finished: null,
      giftsProcessed: 6,
      sent: 2,
      errors: 0,
      mergeFileId: '069000000000001AAA',
      waitingToBeMarkedSent: true
    }
  ]
};

function createComponent() {
  const element = createElement('c-acknowledgments', { is: Acknowledgments });
  document.body.appendChild(element);
  return element;
}

function flush() {
  return Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());
}

describe('c-acknowledgments', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('counts the queue by what each waiting gift would actually get', async () => {
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="email-queue"]').textContent).toBe('4');
    expect(element.shadowRoot.querySelector('[data-id="letter-queue"]').textContent).toBe('2');
    expect(element.shadowRoot.querySelector('[data-id="unmatched-queue"]').textContent).toBe('1');
    expect(element.shadowRoot.querySelector('[data-id="without-recipient"]').textContent).toBe('3');
  });

  it('names a template a rule points at that this org does not have', async () => {
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    const missing = element.shadowRoot.querySelector('[data-id="template-missing"]');
    expect(missing).not.toBeNull();
    expect(missing.textContent.trim()).toBe('Template not found');
  });

  it('describes what each rule matches, and says so when a rule matches everything', async () => {
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    const matches = element.shadowRoot.querySelectorAll('[data-id="rule-matches"]');
    expect(matches[0].textContent.trim()).toBe('1000 and up');
    expect(matches[1].textContent.trim()).toBe('Any gift');
  });

  it('marks an inactive rule as inactive rather than hiding it', async () => {
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    const flags = element.shadowRoot.querySelectorAll('[data-id="rule-active"]');
    expect(flags[0].textContent.trim()).toBe('');
    expect(flags[1].textContent.trim()).toBe('Inactive');
  });

  it('says the last run happened and that nothing is scheduled', async () => {
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="last-run"]').textContent).toContain(
      'Emailed thank yous: 12 sent, 0 did not go.'
    );
    expect(element.shadowRoot.querySelector('[data-id="next-run"]').textContent.trim()).toBe(
      'Not scheduled. Nothing goes out until you press Send.'
    );
  });

  it('says nothing has been sent when no run has ever finished', async () => {
    const element = createComponent();
    getPage.emit({ ...PAGE, lastRun: null, lastRunSummary: null });
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="last-run"]').textContent.trim()).toBe(
      'Nothing has been sent yet.'
    );
  });

  it('offers no send when the queue is empty and none when the user may not send', async () => {
    const element = createComponent();
    getPage.emit({ ...PAGE, emailQueue: 0, letterQueue: 5, canSend: true });
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="send-emails"]').disabled).toBe(true);
    expect(element.shadowRoot.querySelector('[data-id="produce-letters"]').disabled).toBe(false);

    getPage.emit({ ...PAGE, canSend: false });
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="send-emails"]').disabled).toBe(true);
    expect(element.shadowRoot.querySelector('[data-id="produce-letters"]').disabled).toBe(true);
  });

  it('says acknowledgments are off, without hiding the rules', async () => {
    const element = createComponent();
    getPage.emit({ ...PAGE, enabled: false });
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="off-notice"]')).not.toBeNull();
    expect(element.shadowRoot.querySelectorAll('[data-id="rule"]').length).toBe(2);
  });

  it('starts an email send and says it has started', async () => {
    sendEmailsNow.mockResolvedValue({ ...PAGE, emailQueue: 0 });
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    element.shadowRoot.querySelector('[data-id="send-emails"]').click();
    await flush();

    expect(sendEmailsNow).toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('[data-id="notice-message"]').textContent).toContain(
      'The email send has started.'
    );
  });

  it('produces the letter file and offers it for download with a Mark as sent button', async () => {
    produceLetters.mockResolvedValue(PAGE);
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    element.shadowRoot.querySelector('[data-id="produce-letters"]').click();
    await flush();

    expect(produceLetters).toHaveBeenCalled();
    const link = element.shadowRoot.querySelector('[data-id="merge-file"]');
    expect(link.href).toContain('/sfc/servlet.shepherd/document/download/069000000000001AAA');
    expect(element.shadowRoot.querySelector('[data-id="mark-sent"]')).not.toBeNull();
  });

  it('marks a letter run sent, naming the run it means', async () => {
    markLettersSent.mockResolvedValue({ ...PAGE, runs: [] });
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    element.shadowRoot.querySelector('[data-id="mark-sent"]').click();
    await flush();

    expect(markLettersSent).toHaveBeenCalledWith({ runId: 'a07000000000001AAA' });
    expect(element.shadowRoot.querySelector('[data-id="notice-message"]').textContent).toContain(
      'Those letters are recorded as sent.'
    );
  });

  it('shows the message the server sends when a send is refused', async () => {
    sendEmailsNow.mockRejectedValue({
      body: {
        message:
          'Sending thank yous needs the Send Acknowledgments permission. Ask your administrator for the Fundraising Staff role, together with the Giving Staff permission set.'
      }
    });
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    element.shadowRoot.querySelector('[data-id="send-emails"]').click();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error-message"]').textContent).toContain(
      'Send Acknowledgments permission'
    );
  });

  it('reports a failure to read the page', async () => {
    const element = createComponent();
    getPage.error({ message: 'You do not have access to acknowledgments.' });
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error-message"]')).not.toBeNull();
  });
});
