import { createElement } from 'lwc';
import Acknowledgments from 'c/acknowledgments';
import getPage from '@salesforce/apex/AcknowledgmentController.getPage';
import sendEmailsNow from '@salesforce/apex/AcknowledgmentController.sendEmailsNow';
import produceLetters from '@salesforce/apex/AcknowledgmentController.produceLetters';
import markLettersSent from '@salesforce/apex/AcknowledgmentController.markLettersSent';
import reorderRules from '@salesforce/apex/AcknowledgmentController.reorderRules';
import { setHelpTextForTest } from 'c/barnHelpText';

setHelpTextForTest({
  Giving_Acknowledgments_EmailsStarted:
    'The email send has started. The run below shows how it goes.',
  Giving_Acknowledgments_LettersMarkedSent: 'Those letters are recorded as sent.',
  Giving_Acknowledgments_NeverRun: 'Nothing has been sent yet.',
  Giving_Acknowledgments_Off:
    'Acknowledging gifts is switched off, so nothing is joining the queue. Turn on Acknowledge gifts in BarnCRM Settings, under Giving.'
});

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

jest.mock('@salesforce/label/c.Core_MatchLogic_Inactive', () => ({ default: 'Inactive' }), {
  virtual: true
});

jest.mock(
  '@salesforce/label/c.Giving_Acknowledgments_MatchFromAmount',
  () => ({ default: '{0} and up' }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Giving_Acknowledgments_MatchUpToAmount',
  () => ({ default: 'up to {0}' }),
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/AcknowledgmentController.reorderRules',
  () => ({ default: jest.fn() }),
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
  optedOutOfEmail: 1,
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

  it('shows what Setup needs: the From address, email deliverability and templates', async () => {
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    const notes = element.shadowRoot.querySelector('c-settings-setup-notes');
    expect(notes.notes.map((note) => note.key)).toEqual([
      'fromAddress',
      'emailDeliverability',
      'templates'
    ]);
    expect(notes.notes[0].what).toBe('c.Giving_SetupNote_FromAddress_What');
    expect(notes.notes[1].check).toBe('emailDeliverability');
    // Each note opens its own Setup page (keys in Core's c/setupLinks) and lists its clicks.
    expect(notes.notes.map((note) => note.link)).toEqual([
      'orgWideAddresses',
      'deliverability',
      'emailTemplates'
    ]);
    expect(notes.notes[2].steps).toBe('c.Giving_SetupNote_Templates_Steps');
  });

  it('counts the queue by what each waiting gift would actually get', async () => {
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    const tile = (id) => element.shadowRoot.querySelector(`[data-id="${id}"]`).value;
    expect(tile('email-queue')).toBe(4);
    expect(tile('letter-queue')).toBe(2);
    expect(tile('unmatched-queue')).toBe(1);
    expect(tile('without-recipient')).toBe(3);
    expect(tile('opted-out')).toBe(1);
  });

  it('names a template a rule points at that this org does not have', async () => {
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    const missing = element.shadowRoot.querySelector('[data-id="template-missing"]');
    expect(missing).not.toBeNull();
    expect(missing.label).toBe('Template not found');
    expect(missing.status).toBe('error');
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
    expect(flags).toHaveLength(1);
    expect(flags[0].label).toBe('Inactive');
  });

  it('says the last run happened and that nothing is scheduled', async () => {
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="last-run"]').textContent).toContain(
      'Emailed thank yous: 12 sent, 0 did not go.'
    );
    expect(element.shadowRoot.querySelector('[data-id="next-run"]').textContent.trim()).toBe(
      'c.Giving_Acknowledgments_NotScheduled'
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
    expect(element.shadowRoot.querySelector('[data-id="notice-message"]').message).toContain(
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
    expect(element.shadowRoot.querySelector('[data-id="notice-message"]').message).toContain(
      'Those letters are recorded as sent.'
    );
  });

  it('shows the message the server sends when a send is refused', async () => {
    sendEmailsNow.mockRejectedValue({
      body: {
        message:
          'Sending thank yous needs the Send Acknowledgments permission. Ask your administrator for the Fundraising Staff role.'
      }
    });
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    element.shadowRoot.querySelector('[data-id="send-emails"]').click();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error-message"]').message).toContain(
      'Send Acknowledgments permission'
    );
  });

  it('reports a failure to read the page', async () => {
    const element = createComponent();
    getPage.error({ message: 'You do not have access to acknowledgments.' });
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error-message"]')).not.toBeNull();
  });

  it('shows a rule template by the name the administrator recognizes', async () => {
    const element = createComponent();
    const rules = PAGE.rules.map((rule) => {
      if (!rule.template) {
        return rule;
      }
      return { ...rule, templateFound: true, templateLabel: 'BarnCRM: thank you for your gift' };
    });
    getPage.emit({ ...PAGE, rules });
    await flush();

    const shown = element.shadowRoot.querySelectorAll('[data-id="template-name"]')[1];
    expect(shown.textContent.trim()).toBe('BarnCRM: thank you for your gift');
    expect(element.shadowRoot.textContent).not.toContain('BarnCRM_Thank_You');
  });

  it('opens a new rule on the page with a template picker built from the templates', async () => {
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    element.shadowRoot.querySelector('[data-id="new-rule"]').click();
    await flush();

    const form = element.shadowRoot.querySelector('lightning-record-edit-form');
    expect(form).not.toBeNull();
    expect(form.recordId).toBeUndefined();
    const picker = element.shadowRoot.querySelector('[data-id="rule-template"]');
    expect(picker.options).toEqual([
      { label: 'BarnCRM: thank you for your gift', value: 'BarnCRM_Thank_You' }
    ]);
    expect(picker.required).toBe(true);
  });

  it('hides the template picker for a letter rule', async () => {
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    element.shadowRoot.querySelector('[data-id="new-rule"]').click();
    await flush();
    element.shadowRoot
      .querySelector('[data-id="rule-channel"]')
      .dispatchEvent(new CustomEvent('change', { detail: { value: 'Letter' } }));
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="rule-template"]')).toBeNull();
  });

  it('edits an existing rule with its template already chosen', async () => {
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    element.shadowRoot.querySelectorAll('[data-id="rule-edit"]')[1].click();
    await flush();

    expect(element.shadowRoot.querySelector('lightning-record-edit-form').recordId).toBe(
      'a06000000000002AAA'
    );
    expect(element.shadowRoot.querySelector('[data-id="rule-template"]').value).toBe(
      'BarnCRM_Thank_You'
    );
  });

  it('saves the chosen template with the rule', async () => {
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();
    element.shadowRoot.querySelector('[data-id="new-rule"]').click();
    await flush();

    element.shadowRoot
      .querySelector('[data-id="rule-template"]')
      .dispatchEvent(new CustomEvent('change', { detail: { value: 'BarnCRM_Thank_You' } }));
    const form = element.shadowRoot.querySelector('lightning-record-edit-form');
    const submitted = jest.fn();
    form.submit = submitted;
    form.dispatchEvent(
      new CustomEvent('submit', {
        detail: { fields: { Name: 'Everything else' } },
        cancelable: true
      })
    );
    await flush();

    expect(submitted).toHaveBeenCalledWith({
      Name: 'Everything else',
      Email_Template__c: 'BarnCRM_Thank_You'
    });
  });

  it('does not submit an email rule with no template', async () => {
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();
    element.shadowRoot.querySelector('[data-id="new-rule"]').click();
    await flush();

    const form = element.shadowRoot.querySelector('lightning-record-edit-form');
    const submitted = jest.fn();
    form.submit = submitted;
    form.dispatchEvent(
      new CustomEvent('submit', { detail: { fields: { Name: 'No template' } }, cancelable: true })
    );
    await flush();

    expect(submitted).not.toHaveBeenCalled();
  });

  it('closes the form and says so when the rule is saved', async () => {
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();
    element.shadowRoot.querySelector('[data-id="new-rule"]').click();
    await flush();

    element.shadowRoot
      .querySelector('lightning-record-edit-form')
      .dispatchEvent(new CustomEvent('success', { detail: { id: 'a06000000000003AAA' } }));
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="rule-form"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="notice-message"]')).not.toBeNull();
  });

  it('offers no rule editing to somebody who cannot manage settings', async () => {
    const element = createComponent();
    getPage.emit({ ...PAGE, canManage: false });
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="new-rule"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="rule-edit"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="rule-up"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-drag-id]')).toBeNull();
    // The rules section starts closed for staff and open for an admin.
    const section = element.shadowRoot.querySelector('[data-id="rules-section"]');
    expect(section.activeSectionName).toEqual([]);
  });

  it('puts the daily sending first and the rules last, open for an admin', async () => {
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    const order = [
      ...element.shadowRoot.querySelectorAll(
        '[data-id="send-emails"], [data-id="run"], [data-id="rules-section"]'
      )
    ].map((node) => node.dataset.id);
    expect(order).toEqual(['send-emails', 'run', 'rules-section']);
    expect(element.shadowRoot.querySelector('[data-id="rules-section"]').activeSectionName).toBe(
      'rules'
    );
    const badge = element.shadowRoot.querySelector('[data-id="run-status"]');
    expect(badge.status).toBe('attention');
  });

  it('moves a rule down with Move Down, saving the whole order, and announces it', async () => {
    reorderRules.mockResolvedValue(PAGE);
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    const ups = element.shadowRoot.querySelectorAll('[data-id="rule-up"]');
    expect(ups[0].disabled).toBe(true);
    element.shadowRoot.querySelectorAll('[data-id="rule-down"]')[0].click();
    await flush();
    await flush();

    expect(reorderRules).toHaveBeenCalledWith({
      ruleIds: ['a06000000000002AAA', 'a06000000000001AAA']
    });
    expect(element.shadowRoot.querySelector('[data-id="live"]').textContent).toBe(
      'c.Giving_Acknowledgments_RuleMoved'
    );
  });

  it('reorders the rules by keyboard drag', async () => {
    reorderRules.mockResolvedValue(PAGE);
    const element = createComponent();
    getPage.emit(PAGE);
    await flush();

    const row = element.shadowRoot.querySelectorAll('[data-drag-id]')[1];
    const key = (name) => {
      const event = new CustomEvent('keydown', { cancelable: true });
      Object.assign(event, { key: name });
      return event;
    };
    row.dispatchEvent(key(' '));
    row.dispatchEvent(key('ArrowUp'));
    row.dispatchEvent(key('Enter'));
    await flush();
    await flush();

    expect(reorderRules).toHaveBeenCalledWith({
      ruleIds: ['a06000000000002AAA', 'a06000000000001AAA']
    });
  });
});
