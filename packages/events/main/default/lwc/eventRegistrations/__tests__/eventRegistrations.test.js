import { createElement } from 'lwc';
import EventRegistrations from 'c/eventRegistrations';
import getRegistrations from '@salesforce/apex/EventRegistrationsController.getRegistrations';
import register from '@salesforce/apex/EventRegistrationsController.register';
import setStatus from '@salesforce/apex/EventRegistrationsController.setStatus';
import cancelRegistration from '@salesforce/apex/EventRegistrationsController.cancelRegistration';
import BarnConfirmModal from 'c/barnConfirmModal';

jest.mock(
  '@salesforce/apex/EventRegistrationsController.getRegistrations',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/EventRegistrationsController.register',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/EventRegistrationsController.setStatus',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/EventRegistrationsController.cancelRegistration',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const EVENT_ID = 'a01000000000001AAA';
const JANE = 'a09000000000001AAA';
const DATA = {
  capacity: 10,
  currencyCode: 'USD',
  canRegister: true,
  canChange: true,
  truncated: false,
  tickets: [{ value: 't1', label: 'General' }],
  fieldLabels: {
    'Contact.LastName': 'Last Name',
    'Event_Attendee__c.Name': 'Attendee Name',
    'Event_Attendee__c.Status__c': 'Status'
  },
  attendees: [
    {
      id: JANE,
      name: 'Jane Doe',
      contactId: '003000000000001AAA',
      ticketName: 'General',
      price: 20,
      status: 'Registered',
      registrationId: 'a08000000000001AAA',
      registrationName: 'REG-000001',
      registrationStatus: 'Registered',
      source: 'Staff'
    },
    {
      id: 'a09000000000002AAA',
      name: 'Max Doe',
      ticketName: 'General',
      price: 0,
      status: 'Waitlisted',
      registrationId: 'a08000000000002AAA',
      registrationName: 'REG-000002',
      registrationStatus: 'Waitlisted',
      source: 'Form'
    }
  ]
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(data = DATA) {
  getRegistrations.mockResolvedValue(data);
  const element = createElement('c-event-registrations', { is: EventRegistrations });
  element.recordId = EVENT_ID;
  document.body.appendChild(element);
  await flush();
  return element;
}

const all = (element, selector) => [...element.shadowRoot.querySelectorAll(selector)];
const one = (element, selector) => element.shadowRoot.querySelector(selector);
const choose = (menu, value) =>
  menu.dispatchEvent(new CustomEvent('select', { detail: { value } }));

describe('c-event-registrations', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists attendees with their status badges', async () => {
    const element = await render();
    expect(getRegistrations).toHaveBeenCalledWith({ eventId: EVENT_ID });
    expect(all(element, '[data-id="attendee-row"]')).toHaveLength(2);
    const badges = all(element, 'c-barn-status-badge');
    expect(badges[0].status).toBe('new');
    expect(badges[1].status).toBe('pending');
    expect(one(element, '[data-id="summary"]')).not.toBeNull();
  });

  it('shows the empty state and no button for a person who cannot register', async () => {
    const element = await render({ ...DATA, canRegister: false, attendees: [] });
    expect(one(element, '[data-id="empty-state"]')).not.toBeNull();
    expect(one(element, '[data-id="new-registration"]')).toBeNull();
  });

  it('registers a typed person with a guest and reloads', async () => {
    const element = await render();
    register.mockResolvedValue({ registered: 2, waitlisted: 0, alreadyRegistered: [] });
    one(element, '[data-id="new-registration"]').click();
    await flush();
    expect(one(element, '[data-id="form-register"]').disabled).toBe(true);
    one(element, '[data-field="lastName"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Lee' } })
    );
    one(element, '[data-id="add-guest"]').click();
    await flush();
    const guestLast = all(element, '[data-id="guest-row"] [data-field="lastName"]')[0];
    guestLast.dispatchEvent(new CustomEvent('change', { detail: { value: 'Lee' } }));
    await flush();
    one(element, '[data-id="form-register"]').click();
    await flush();
    const sent = JSON.parse(register.mock.calls[0][0].requestJson);
    expect(sent.eventId).toBe(EVENT_ID);
    expect(sent.registrant.lastName).toBe('Lee');
    expect(sent.ticketType).toBe('t1');
    expect(sent.guests).toHaveLength(1);
    expect(getRegistrations).toHaveBeenCalledTimes(2);
  });

  it('marks an attendee attended from the menu', async () => {
    const element = await render();
    setStatus.mockResolvedValue('Attended');
    choose(all(element, 'lightning-button-menu')[0], 'markAttended');
    await flush();
    expect(setStatus).toHaveBeenCalledWith({ attendeeId: JANE, status: 'Attended' });
  });

  it('cancels a registration once confirmed', async () => {
    const element = await render();
    BarnConfirmModal.open = jest.fn().mockResolvedValue(true);
    cancelRegistration.mockResolvedValue();
    choose(all(element, 'lightning-button-menu')[0], 'cancelRegistration');
    await flush();
    await flush();
    expect(cancelRegistration).toHaveBeenCalledWith({ registrationId: 'a08000000000001AAA' });
  });

  it('shows the load failure', async () => {
    getRegistrations.mockRejectedValue({ body: { message: 'Boom' } });
    const element = createElement('c-event-registrations', { is: EventRegistrations });
    element.recordId = EVENT_ID;
    document.body.appendChild(element);
    await flush();
    expect(one(element, '[data-id="error-message"]')).not.toBeNull();
  });
});
