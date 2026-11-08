import { createElement } from 'lwc';
import EventAppointments from 'c/eventAppointments';
import getAppointments from '@salesforce/apex/EventAppointmentsController.getAppointments';
import addSlots from '@salesforce/apex/EventAppointmentsController.addSlots';
import book from '@salesforce/apex/EventAppointmentsController.book';
import setStatus from '@salesforce/apex/EventAppointmentsController.setStatus';

jest.mock(
  '@salesforce/apex/EventAppointmentsController.getAppointments',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/EventAppointmentsController.addSlots', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/EventAppointmentsController.book', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/EventAppointmentsController.setStatus',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('lightning/uiRecordApi', () => ({ deleteRecord: jest.fn() }), { virtual: true });

const EVENT_ID = 'a01000000000001AAA';
const PRIYA = '003000000000001AAA';
const OMAR = '003000000000002AAA';
const at = (h, m = 0) => new Date(2027, 5, 4, h, m).toISOString();

function dataWith(extra = {}) {
  return {
    canAdd: true,
    canBook: true,
    eventStart: at(8),
    eventEnd: at(18),
    fieldLabels: {
      Host__c: 'Host',
      Contact__c: 'Person',
      Status__c: 'Status',
      Location__c: 'Location',
      Start__c: 'Start'
    },
    slots: [
      {
        id: 'a1',
        name: 'Priya 9:00 AM',
        hostId: PRIYA,
        hostName: 'Priya Rao',
        start: at(9),
        finish: at(9, 20),
        status: 'Open'
      },
      {
        id: 'a2',
        name: 'Priya 9:20 AM',
        hostId: PRIYA,
        hostName: 'Priya Rao',
        contactId: OMAR,
        contactName: 'Omar Hill',
        start: at(9, 20),
        finish: at(9, 40),
        status: 'Booked'
      }
    ],
    ...extra
  };
}

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(data = dataWith()) {
  getAppointments.mockResolvedValue(data);
  const element = createElement('c-event-appointments', { is: EventAppointments });
  element.recordId = EVENT_ID;
  document.body.appendChild(element);
  await flush();
  return element;
}

const one = (element, selector) => element.shadowRoot.querySelector(selector);
const all = (element, selector) => [...element.shadowRoot.querySelectorAll(selector)];
const menuOf = (element, id) => one(element, `lightning-button-menu[data-id="${id}"]`);
const choose = (menu, value) =>
  menu.dispatchEvent(new CustomEvent('select', { detail: { value } }));

describe('c-event-appointments', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists a host with their slots, status and person', async () => {
    const element = await render();
    expect(getAppointments).toHaveBeenCalledWith({ eventId: EVENT_ID });
    expect(all(element, '[data-id="host-group"]')).toHaveLength(1);
    const rows = all(element, '[data-id="slot-row"]');
    expect(rows).toHaveLength(2);
    expect(rows[1].textContent).toContain('Omar Hill');
    expect(all(element, 'c-barn-status-badge').map((b) => b.status)).toEqual(['pending', 'active']);
  });

  it('shows the empty state, and no add form to a person who cannot add', async () => {
    const element = await render(dataWith({ canAdd: false, slots: [] }));
    expect(one(element, '[data-id="empty-state"]')).not.toBeNull();
    expect(one(element, '[data-id="add-form"]')).toBeNull();
  });

  it('previews and adds the slots for the chosen host', async () => {
    const element = await render(dataWith({ slots: [] }));
    expect(one(element, '[data-id="add"]').disabled).toBe(true);
    one(element, '[data-id="host"]').dispatchEvent(
      new CustomEvent('change', { detail: { recordId: PRIYA } })
    );
    one(element, '[data-id="date"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: '2027-06-04' } })
    );
    await flush();
    expect(one(element, '[data-id="add"]').disabled).toBe(false);
    addSlots.mockResolvedValue(9);
    one(element, '[data-id="add"]').click();
    await flush();
    const call = addSlots.mock.calls[0][0];
    expect(call.hostId).toBe(PRIYA);
    expect(JSON.parse(call.slotsJson)).toHaveLength(9);
    expect(JSON.parse(call.slotsJson)[0].finish).toBeTruthy();
    expect(getAppointments).toHaveBeenCalledTimes(2);
  });

  it('warns when the slots fall outside the event', async () => {
    const element = await render(dataWith({ slots: [], eventEnd: at(10) }));
    one(element, '[data-id="date"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: '2027-06-04' } })
    );
    await flush();
    expect(one(element, '[data-id="outside"]')).not.toBeNull();
  });

  it('books a person into an open slot from its menu', async () => {
    const element = await render();
    choose(menuOf(element, 'a1'), 'book');
    await flush();
    const picker = one(element, 'lightning-record-picker[data-id="a1"]');
    expect(picker).not.toBeNull();
    book.mockResolvedValue();
    picker.dispatchEvent(new CustomEvent('change', { detail: { recordId: OMAR } }));
    await flush();
    expect(book).toHaveBeenCalledWith({ appointmentId: 'a1', contactId: OMAR });
    expect(getAppointments).toHaveBeenCalledTimes(2);
  });

  it('moves a booked slot to Completed and releases it', async () => {
    const element = await render();
    setStatus.mockResolvedValue();
    choose(menuOf(element, 'a2'), 'complete');
    await flush();
    expect(setStatus).toHaveBeenCalledWith({ appointmentId: 'a2', status: 'Completed' });
    choose(menuOf(element, 'a2'), 'release');
    await flush();
    expect(setStatus).toHaveBeenLastCalledWith({ appointmentId: 'a2', status: 'Open' });
  });

  it('flags two overlapping slots of one host', async () => {
    const element = await render(
      dataWith({
        slots: [
          {
            id: 'b1',
            name: 'x',
            hostId: PRIYA,
            hostName: 'Priya Rao',
            start: at(9),
            finish: at(10),
            status: 'Open'
          },
          {
            id: 'b2',
            name: 'y',
            hostId: PRIYA,
            hostName: 'Priya Rao',
            start: at(9, 30),
            finish: at(10, 30),
            status: 'Open'
          }
        ]
      })
    );
    expect(all(element, '[data-id="clash"]')).toHaveLength(2);
  });

  it('shows the load error', async () => {
    getAppointments.mockRejectedValue({ body: { message: 'Broken' } });
    const element = createElement('c-event-appointments', { is: EventAppointments });
    element.recordId = EVENT_ID;
    document.body.appendChild(element);
    await flush();
    expect(one(element, '[data-id="error-message"]')).not.toBeNull();
  });
});
