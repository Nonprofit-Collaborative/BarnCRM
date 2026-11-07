import { createElement } from 'lwc';
import EventAgenda from 'c/eventAgenda';
import getAgenda from '@salesforce/apex/EventAgendaController.getAgenda';
import moveSession from '@salesforce/apex/EventAgendaController.moveSession';
import EventRecordModal from 'c/eventRecordModal';

jest.mock('@salesforce/apex/EventAgendaController.getAgenda', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/EventAgendaController.moveSession', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('lightning/uiRecordApi', () => ({ deleteRecord: jest.fn() }), { virtual: true });
jest.mock('@salesforce/i18n/locale', () => ({ default: 'en-US' }), { virtual: true });
jest.mock('@salesforce/i18n/timeZone', () => ({ default: 'UTC' }), { virtual: true });
jest.mock('@salesforce/label/c.Core_Shared_MoveTo', () => ({ default: 'Move to {0}' }), {
  virtual: true
});

const EVENT_ID = 'a01000000000001AAA';
const ADMINS = 'a04000000000001AAA';
const AGENDA = {
  canMove: true,
  canAddTrack: true,
  canAddSession: true,
  tracks: [{ id: ADMINS, name: 'Admins' }],
  sessions: [
    {
      id: 'S1',
      name: 'Flows 101',
      trackId: ADMINS,
      startsAt: '2027-05-01T09:00:00.000Z',
      endsAt: '2027-05-01T10:00:00.000Z',
      room: 'Hall A',
      status: 'Confirmed',
      sessionType: 'Talk'
    },
    {
      id: 'S2',
      name: 'Keynote',
      startsAt: '2027-05-01T09:30:00.000Z',
      endsAt: '2027-05-01T10:30:00.000Z',
      room: 'hall a',
      status: 'Confirmed',
      sessionType: 'Keynote'
    },
    { id: 'S3', name: 'Lightning Talks', status: 'Draft', sessionType: 'Talk' }
  ]
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(agenda = AGENDA) {
  getAgenda.mockResolvedValue(agenda);
  const element = createElement('c-event-agenda', { is: EventAgenda });
  element.recordId = EVENT_ID;
  document.body.appendChild(element);
  await flush();
  return element;
}

const all = (element, selector) => [...element.shadowRoot.querySelectorAll(selector)];
const one = (element, selector) => element.shadowRoot.querySelector(selector);

describe('c-event-agenda', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('draws a column per track then No Track, with clashes flagged', async () => {
    const element = await render();
    const columns = all(element, '[data-id="column"]');
    expect(columns.map((column) => column.dataset.column)).toEqual([ADMINS, 'none']);
    expect(columns[0].querySelectorAll('[data-id="session-card"]')).toHaveLength(1);
    expect(columns[1].querySelectorAll('[data-id="session-card"]')).toHaveLength(2);
    const clashes = all(element, '[data-id="clashes"]');
    expect(clashes).toHaveLength(2);
    expect(clashes[0].textContent).toContain('Events_Agenda_RoomClash');
  });

  it('offers days with Unscheduled last and filters the board', async () => {
    const element = await render();
    const day = one(element, '[data-id="day"]');
    expect(day.options.map((option) => option.value)).toEqual(['', '2027-05-01', 'unscheduled']);
    day.dispatchEvent(new CustomEvent('change', { detail: { value: 'unscheduled' } }));
    await flush();
    expect(all(element, '[data-id="session-card"]')).toHaveLength(1);
  });

  it('moves a session by its menu, changing only its track', async () => {
    const element = await render();
    moveSession.mockResolvedValue();
    const menu = element.shadowRoot.querySelector('lightning-button-menu[data-id="S1"]');
    const values = [...menu.querySelectorAll('lightning-menu-item')].map((item) => item.value);
    expect(values).toEqual(['edit', 'move:none', 'delete']);
    menu.dispatchEvent(new CustomEvent('select', { detail: { value: 'move:none' } }));
    await flush();
    expect(moveSession).toHaveBeenCalledWith({ sessionId: 'S1', trackId: null });
    expect(getAgenda).toHaveBeenCalledTimes(2);
  });

  it('moves a session by keyboard on its drag handle', async () => {
    const element = await render();
    moveSession.mockResolvedValue();
    const handle = one(element, '[data-drag-id="S1"]');
    const key = (name) =>
      handle.dispatchEvent(new KeyboardEvent('keydown', { key: name, bubbles: true }));
    key(' ');
    await flush();
    key('ArrowRight');
    await flush();
    key(' ');
    await flush();
    expect(moveSession).toHaveBeenCalledWith({ sessionId: 'S1', trackId: null });
  });

  it('gives drag handles only to a person who may move sessions', async () => {
    let element = await render();
    expect(all(element, '[data-drag-id]')).toHaveLength(3);
    expect(one(element, '[data-id="drag-announcer"]')).not.toBeNull();
    document.body.removeChild(element);
    element = await render({ ...AGENDA, canMove: false, canAddTrack: false });
    expect(all(element, '[data-drag-id]')).toHaveLength(0);
    expect(one(element, '[data-id="new-track"]')).toBeNull();
  });

  it('opens the new session form for this event', async () => {
    const element = await render();
    EventRecordModal.open.mockResolvedValueOnce(undefined);
    one(element, '[data-id="new-session"]').click();
    await flush();
    expect(EventRecordModal.open).toHaveBeenCalledWith(
      expect.objectContaining({
        objectApiName: 'Event_Session__c',
        defaults: { Event__c: EVENT_ID }
      })
    );
    expect(getAgenda).toHaveBeenCalledTimes(1);
  });

  it('shows the empty state when there is nothing yet', async () => {
    const element = await render({ ...AGENDA, tracks: [], sessions: [] });
    expect(one(element, '[data-id="empty-state"]')).not.toBeNull();
    expect(one(element, '[data-id="board"]')).toBeNull();
  });
});
