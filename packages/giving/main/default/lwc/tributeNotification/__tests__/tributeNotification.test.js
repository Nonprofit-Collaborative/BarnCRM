import { createElement } from 'lwc';
import TributeNotification from 'c/tributeNotification';
import getTribute from '@salesforce/apex/TributeController.getTribute';
import markNotificationSent from '@salesforce/apex/TributeController.markNotificationSent';

jest.mock(
  '@salesforce/apex/TributeController.getTribute',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/TributeController.markNotificationSent',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock('@salesforce/apex', () => ({ refreshApex: jest.fn(() => Promise.resolve()) }), {
  virtual: true
});

jest.mock(
  '@salesforce/label/c.Giving_TributeNotification_None',
  () => ({ default: 'This gift was not given in honor of or in memory of anyone.' }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Giving_TributeNotification_NotSent',
  () => ({ default: 'Not sent yet' }),
  {
    virtual: true
  }
);

jest.mock(
  '@salesforce/label/c.Giving_TributeNotification_Sent',
  () => ({ default: 'Notification sent' }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Giving_TributeNotification_NotifyPrefix',
  () => ({ default: 'notify' }),
  {
    virtual: true
  }
);

const GIFT_ID = 'a02000000000001AAA';

const TRIBUTE = {
  recordId: 'a04000000000001AAA',
  name: 'TR-000001',
  tributeType: 'In memory of',
  honoreeName: 'Rosa Garcia',
  recipientName: 'Ana Garcia',
  message: 'With love from the Tuesday reading group',
  notificationSent: false,
  notificationSentDate: null,
  canMarkSent: true
};

function createComponent() {
  const element = createElement('c-tribute-notification', { is: TributeNotification });
  element.recordId = GIFT_ID;
  document.body.appendChild(element);
  return element;
}

function flush() {
  return Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());
}

describe('c-tribute-notification', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('summarizes the tribute in one line and never states an amount', async () => {
    const element = createComponent();
    getTribute.emit(TRIBUTE);
    await flush();

    const summary = element.shadowRoot.querySelector('[data-id="summary"]').textContent;
    expect(summary).toContain('In memory of Rosa Garcia');
    expect(summary).toContain('notify Ana Garcia');
    expect(summary).not.toMatch(/[0-9]/);
  });

  it('says the notification has not gone out yet', async () => {
    const element = createComponent();
    getTribute.emit(TRIBUTE);
    await flush();

    const badge = element.shadowRoot.querySelector('c-barn-status-badge');
    expect(badge.label).toContain('Not sent yet');
    expect(badge.status).toBe('pending');
    expect(element.shadowRoot.querySelector('[data-id="mark-sent"]')).not.toBeNull();
  });

  it('records that the notification has been sent and hides the button', async () => {
    markNotificationSent.mockResolvedValue({
      ...TRIBUTE,
      notificationSent: true,
      notificationSentDate: '2026-09-07',
      canMarkSent: false
    });
    const element = createComponent();
    getTribute.emit(TRIBUTE);
    await flush();

    element.shadowRoot.querySelector('[data-id="mark-sent"]').click();
    await flush();

    expect(markNotificationSent).toHaveBeenCalledWith({ tributeId: TRIBUTE.recordId });
    const badge = element.shadowRoot.querySelector('c-barn-status-badge');
    expect(badge.label).toContain('Notification sent');
    expect(badge.status).toBe('done');
    expect(element.shadowRoot.querySelector('[data-id="mark-sent"]')).toBeNull();
  });

  it('says why there is no button when nobody is recorded to notify', async () => {
    const element = createComponent();
    getTribute.emit({
      ...TRIBUTE,
      recipientName: null,
      canMarkSent: false,
      blockedReason: 'Nobody is recorded as the person to notify, so there is no letter to send.'
    });
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="mark-sent"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="blocked-reason"]').message).toContain(
      'Nobody is recorded as the person to notify'
    );
    expect(element.shadowRoot.querySelector('[data-id="summary"]').textContent).toContain(
      'In memory of Rosa Garcia'
    );
  });

  it('says nothing was honored when the gift has no tribute', async () => {
    const element = createComponent();
    getTribute.emit(null);
    await flush();

    const empty = element.shadowRoot.querySelector('[data-id="empty-state"]');
    expect(empty.size).toBe('compact');
    expect(empty.message).toBe('c.Giving_TributeNotification_Empty');
    expect(element.shadowRoot.querySelector('[data-id="summary"]')).toBeNull();
  });

  it('shows the message the server sends when marking sent is refused', async () => {
    markNotificationSent.mockRejectedValue({
      body: { message: 'That tribute is no longer here, or you do not have access to it.' }
    });
    const element = createComponent();
    getTribute.emit(TRIBUTE);
    await flush();

    element.shadowRoot.querySelector('[data-id="mark-sent"]').click();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error-message"]').message).toBe(
      'That tribute is no longer here, or you do not have access to it.'
    );
  });

  it('reports a failure to load the tribute', async () => {
    const element = createComponent();
    getTribute.error({ message: 'You do not have access to tributes.' });
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error-message"]')).not.toBeNull();
  });
});
