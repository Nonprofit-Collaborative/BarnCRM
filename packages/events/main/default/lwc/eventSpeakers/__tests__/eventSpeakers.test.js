import { createElement } from 'lwc';
import EventSpeakers from 'c/eventSpeakers';
import getSpeakers from '@salesforce/apex/EventSpeakersController.getSpeakers';
import addSpeaker from '@salesforce/apex/EventSpeakersController.addSpeaker';
import assign from '@salesforce/apex/EventSpeakersController.assign';
import removeSpeaker from '@salesforce/apex/EventSpeakersController.removeSpeaker';
import { deleteRecord } from 'lightning/uiRecordApi';
import EventRecordModal from 'c/eventRecordModal';

jest.mock('@salesforce/apex/EventSpeakersController.getSpeakers', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/EventSpeakersController.addSpeaker', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/EventSpeakersController.assign', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/EventSpeakersController.removeSpeaker',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('lightning/uiRecordApi', () => ({ deleteRecord: jest.fn() }), { virtual: true });

const EVENT_ID = 'a01000000000001AAA';
const ANA = 'a05000000000001AAA';
const KEYNOTE = 'a04000000000001AAA';
const DATA = {
  canAdd: true,
  canAssign: true,
  fieldLabels: { Name: 'Speaker Name', Sessions: 'Sessions', Role__c: 'Role' },
  sessions: [{ label: 'Keynote', value: KEYNOTE }],
  roles: [
    { label: 'Speaker', value: 'Speaker' },
    { label: 'Moderator', value: 'Moderator' }
  ],
  speakers: [
    {
      id: ANA,
      name: 'Ana Garcia',
      contactId: '003000000000001AAA',
      headline: 'Architect',
      status: 'Confirmed',
      assignments: [
        { id: 'a06000000000001AAA', sessionId: KEYNOTE, sessionName: 'Keynote', role: 'Speaker' }
      ]
    },
    {
      id: 'a05000000000002AAA',
      name: 'Sam Lee',
      headline: null,
      status: 'Invited',
      assignments: []
    }
  ]
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(data = DATA) {
  getSpeakers.mockResolvedValue(data);
  const element = createElement('c-event-speakers', { is: EventSpeakers });
  element.recordId = EVENT_ID;
  document.body.appendChild(element);
  await flush();
  return element;
}

const all = (element, selector) => [...element.shadowRoot.querySelectorAll(selector)];
const one = (element, selector) => element.shadowRoot.querySelector(selector);
const menuOf = (element, index) => all(element, 'lightning-button-menu')[index];
const choose = (menu, value) =>
  menu.dispatchEvent(new CustomEvent('select', { detail: { value } }));

describe('c-event-speakers', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists speakers with their status and sessions', async () => {
    const element = await render();
    expect(getSpeakers).toHaveBeenCalledWith({ eventId: EVENT_ID });
    const rows = all(element, '[data-id="speaker-row"]');
    expect(rows).toHaveLength(2);
    expect(rows[0].textContent).toContain('Keynote (Speaker)');
    const badges = all(element, 'c-barn-status-badge');
    expect(badges[0].status).toBe('active');
    expect(badges[1].status).toBe('pending');
    expect(one(element, 'a').getAttribute('href')).toBe('/lightning/r/003000000000001AAA/view');
  });

  it('shows the empty state and no picker for a person who cannot add', async () => {
    const element = await render({ ...DATA, canAdd: false, speakers: [] });
    expect(one(element, '[data-id="empty-state"]')).not.toBeNull();
    expect(one(element, '[data-id="add-speaker"]')).toBeNull();
  });

  it('adds the picked person as a speaker and reloads', async () => {
    const element = await render();
    addSpeaker.mockResolvedValue('a05000000000009AAA');
    one(element, '[data-id="add-speaker"]').dispatchEvent(
      new CustomEvent('change', { detail: { recordId: '003000000000002AAA' } })
    );
    await flush();
    expect(addSpeaker).toHaveBeenCalledWith({
      eventId: EVENT_ID,
      contactId: '003000000000002AAA'
    });
    expect(getSpeakers).toHaveBeenCalledTimes(2);
  });

  it('puts a speaker in a session with a role', async () => {
    const element = await render();
    assign.mockResolvedValue();
    choose(menuOf(element, 1), 'assign');
    await flush();
    const form = one(element, '[data-id="assign-form"]');
    expect(form).not.toBeNull();
    expect(one(element, '[data-id="assign-save"]').disabled).toBe(true);
    one(element, '[data-id="assign-session"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: KEYNOTE } })
    );
    one(element, '[data-id="assign-role"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Moderator' } })
    );
    await flush();
    one(element, '[data-id="assign-save"]').click();
    await flush();
    expect(assign).toHaveBeenCalledWith({
      sessionId: KEYNOTE,
      speakerId: 'a05000000000002AAA',
      role: 'Moderator'
    });
    expect(one(element, '[data-id="assign-form"]')).toBeNull();
  });

  it('removes an assignment and edits a speaker', async () => {
    const element = await render();
    deleteRecord.mockResolvedValue();
    one(element, '[data-id="assignment"] lightning-button-icon').click();
    await flush();
    expect(deleteRecord).toHaveBeenCalledWith('a06000000000001AAA');

    EventRecordModal.open.mockResolvedValueOnce({ id: ANA });
    choose(menuOf(element, 0), 'edit');
    await flush();
    expect(EventRecordModal.open).toHaveBeenCalledWith(
      expect.objectContaining({ objectApiName: 'Event_Speaker__c', recordId: ANA })
    );
  });

  it('removes a speaker after the person confirms', async () => {
    const element = await render();
    EventRecordModal.open.mockResolvedValueOnce(true);
    removeSpeaker.mockResolvedValue();
    choose(menuOf(element, 0), 'remove');
    await flush();
    await flush();
    expect(removeSpeaker).toHaveBeenCalledWith({ speakerId: ANA });
  });

  it('shows a refusal in a toast and the load error', async () => {
    const element = await render();
    removeSpeaker.mockRejectedValue({ body: { message: 'Not yours' } });
    const toasts = jest.fn();
    element.addEventListener('lightning__showtoast', toasts);
    EventRecordModal.open.mockResolvedValueOnce(true);
    choose(menuOf(element, 0), 'remove');
    await flush();
    await flush();
    expect(toasts).toHaveBeenCalled();

    getSpeakers.mockRejectedValue({ body: { message: 'No access' } });
    const broken = createElement('c-event-speakers', { is: EventSpeakers });
    broken.recordId = EVENT_ID;
    document.body.appendChild(broken);
    await flush();
    expect(one(broken, '[data-id="error-message"]').message).toBe('No access');
  });
});
