import { createElement } from 'lwc';
import EventTickets from 'c/eventTickets';
import getTickets from '@salesforce/apex/EventTicketsController.getTickets';
import { deleteRecord } from 'lightning/uiRecordApi';
import EventRecordModal from 'c/eventRecordModal';

jest.mock('@salesforce/apex/EventTicketsController.getTickets', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('lightning/uiRecordApi', () => ({ deleteRecord: jest.fn() }), { virtual: true });
jest.mock('@salesforce/i18n/locale', () => ({ default: 'en-US' }), { virtual: true });
jest.mock('@salesforce/i18n/timeZone', () => ({ default: 'UTC' }), { virtual: true });

const EVENT_ID = 'a01000000000001AAA';
const GENERAL = 'a02000000000001AAA';
const DATA = {
  capacity: 100,
  currencyCode: 'USD',
  codesTitle: 'Promo Codes',
  canAddTicket: true,
  canAddCode: true,
  fieldLabels: { 'Ticket_Type__c.Name': 'Ticket Type Name', 'Promo_Code__c.Name': 'Code' },
  tickets: [
    { id: GENERAL, name: 'General', price: 50, quantity: 80, active: true },
    { id: 'a02000000000002AAA', name: 'Student', price: 20, quantity: 40, active: true }
  ],
  codes: [
    {
      id: 'a03000000000001AAA',
      code: 'EARLY',
      discountType: 'Percent',
      discountValue: 10,
      ticketTypeId: GENERAL,
      active: true
    },
    {
      id: 'a03000000000002AAA',
      code: 'TENOFF',
      discountType: 'Amount',
      discountValue: 10,
      active: true,
      validUntil: '2020-01-01T00:00:00.000Z'
    }
  ]
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(data = DATA) {
  getTickets.mockResolvedValue(data);
  const element = createElement('c-event-tickets', { is: EventTickets });
  element.recordId = EVENT_ID;
  document.body.appendChild(element);
  await flush();
  return element;
}

const all = (element, selector) => [...element.shadowRoot.querySelectorAll(selector)];
const one = (element, selector) => element.shadowRoot.querySelector(selector);

describe('c-event-tickets', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists ticket types and codes with prices, discounts and states', async () => {
    const element = await render();
    expect(getTickets).toHaveBeenCalledWith({ eventId: EVENT_ID });
    const tickets = all(element, '[data-id="ticket-row"]');
    expect(tickets).toHaveLength(2);
    expect(tickets[0].textContent).toContain('$50.00');
    const codes = all(element, '[data-id="code-row"]');
    expect(codes[0].textContent).toContain('10%');
    expect(codes[0].textContent).toContain('General');
    expect(codes[1].textContent).toContain('$10.00');
    const badges = all(element, '[data-id="code-row"] c-barn-status-badge');
    expect(badges[1].status).toBe('closed');
    expect(one(element, '[data-id="capacity-warning"]').message).toContain(
      'Events_Tickets_OverCapacity'
    );
  });

  it('shows empty states and no buttons for a person who cannot add', async () => {
    const element = await render({
      ...DATA,
      canAddTicket: false,
      canAddCode: false,
      tickets: [],
      codes: []
    });
    expect(one(element, '[data-id="no-tickets"]')).not.toBeNull();
    expect(one(element, '[data-id="no-codes"]')).not.toBeNull();
    expect(one(element, '[data-id="new-ticket"]')).toBeNull();
    expect(one(element, '[data-id="capacity-warning"]')).toBeNull();
  });

  it('opens the form for a new ticket type in this event and reloads once saved', async () => {
    const element = await render();
    EventRecordModal.open.mockResolvedValueOnce({ id: 'a02000000000009AAA' });
    one(element, '[data-id="new-ticket"]').click();
    await flush();
    expect(EventRecordModal.open).toHaveBeenCalledWith(
      expect.objectContaining({
        objectApiName: 'Ticket_Type__c',
        defaults: { Event__c: EVENT_ID }
      })
    );
    expect(getTickets).toHaveBeenCalledTimes(2);
  });

  it('deletes a code after the person confirms', async () => {
    const element = await render();
    EventRecordModal.open.mockResolvedValueOnce(true);
    deleteRecord.mockResolvedValue();
    const menus = all(element, 'lightning-button-menu');
    menus[2].dispatchEvent(new CustomEvent('select', { detail: { value: 'delete' } }));
    await flush();
    await flush();
    expect(deleteRecord).toHaveBeenCalledWith('a03000000000001AAA');
    expect(getTickets).toHaveBeenCalledTimes(2);
  });

  it('shows the load error', async () => {
    getTickets.mockRejectedValue({ body: { message: 'No access' } });
    const element = createElement('c-event-tickets', { is: EventTickets });
    element.recordId = EVENT_ID;
    document.body.appendChild(element);
    await flush();
    expect(one(element, '[data-id="error-message"]').message).toBe('No access');
  });
});
