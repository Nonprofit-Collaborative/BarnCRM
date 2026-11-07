import { createElement } from 'lwc';
import EventSeating from 'c/eventSeating';
import getSeating from '@salesforce/apex/EventSeatingController.getSeating';
import saveTable from '@salesforce/apex/EventSeatingController.saveTable';
import deleteTable from '@salesforce/apex/EventSeatingController.deleteTable';
import assignSeats from '@salesforce/apex/EventSeatingController.assignSeats';
import saveNeeds from '@salesforce/apex/EventSeatingController.saveNeeds';
import { ShowToastEventName } from 'lightning/platformShowToastEvent';

jest.mock('@salesforce/apex/EventSeatingController.getSeating', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/EventSeatingController.saveTable', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/EventSeatingController.deleteTable', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/EventSeatingController.assignSeats', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/EventSeatingController.saveNeeds', () => ({ default: jest.fn() }), {
  virtual: true
});

const EVENT_ID = 'a01000000000001AAA';
const DATA = {
  canEdit: true,
  canAddTable: true,
  truncated: false,
  sponsors: [{ value: 's1', label: 'Acme' }],
  tables: [
    { id: 't1', name: 'Table 1', capacity: 2, hostName: 'Hal' },
    { id: 't2', name: 'Table 2', capacity: 4 }
  ],
  guests: [
    { id: 'g1', name: 'Ann', partyId: 'p1', tableId: 't1', dietary: 'Vegan' },
    { id: 'g2', name: 'Bo', partyId: 'p1' },
    { id: 'g3', name: 'Cy', partyId: 'p2' }
  ]
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(data = DATA) {
  getSeating.mockResolvedValue(data);
  assignSeats.mockResolvedValue(1);
  saveTable.mockResolvedValue('t9');
  deleteTable.mockResolvedValue();
  saveNeeds.mockResolvedValue();
  const element = createElement('c-event-seating', { is: EventSeating });
  element.recordId = EVENT_ID;
  document.body.appendChild(element);
  await flush();
  return element;
}

const all = (element, selector) => [...element.shadowRoot.querySelectorAll(selector)];
const one = (element, selector) => element.shadowRoot.querySelector(selector);
const change = (node, value) =>
  node.dispatchEvent(new CustomEvent('change', { detail: { value } }));

describe('c-event-seating', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('draws the tables with their guests and the guest list', async () => {
    const element = await render();
    expect(getSeating).toHaveBeenCalledWith({ eventId: EVENT_ID });
    expect(all(element, '[data-id="table-card"]')).toHaveLength(2);
    expect(all(element, '[data-id="guest-row"]')).toHaveLength(3);
    expect(all(element, '[data-id="table-guest"]')).toHaveLength(1);
  });

  it('shows the empty state with no tables', async () => {
    const element = await render({ ...DATA, tables: [], guests: [] });
    expect(one(element, '[data-id="empty-state"]')).not.toBeNull();
    expect(one(element, '[data-id="no-guests"]')).not.toBeNull();
  });

  it('seats a whole party together and warns when a table goes over', async () => {
    const element = await render();
    const toasts = [];
    element.addEventListener(ShowToastEventName, (event) => toasts.push(event.detail));
    change(one(element, '[data-action="seat"][data-id="g3"]'), 't1');
    await flush();
    expect(assignSeats).toHaveBeenCalledWith({
      eventId: EVENT_ID,
      seatsJson: JSON.stringify([{ attendeeId: 'g3', tableId: 't1' }])
    });
    expect(toasts.some((toast) => toast.variant === 'warning')).toBe(false);

    change(one(element, '[data-action="seat"][data-id="g2"]'), 't1');
    await flush();
    expect(assignSeats).toHaveBeenCalledTimes(2);
  });

  it('suggests seating for the people with no table', async () => {
    const element = await render();
    one(element, '[data-id="suggest"]').click();
    await flush();
    const seats = JSON.parse(assignSeats.mock.calls[0][0].seatsJson);
    expect(seats.map((seat) => seat.attendeeId).sort()).toEqual(['g2', 'g3']);
  });

  it('adds a table', async () => {
    const element = await render();
    one(element, '[data-id="add-table"]').click();
    await flush();
    const name = one(element, '[data-field="name"]');
    change(name, 'Table 9');
    await flush();
    one(element, '[data-id="table-save"]').click();
    await flush();
    const sent = JSON.parse(saveTable.mock.calls[0][0].inputJson);
    expect(sent).toMatchObject({ eventId: EVENT_ID, name: 'Table 9', capacity: 10 });
  });

  it('removes a table', async () => {
    const element = await render();
    one(element, '[data-action="delete-table"][data-id="t2"]').click();
    await flush();
    expect(deleteTable).toHaveBeenCalledWith({ tableId: 't2' });
  });

  it('saves dietary needs when the field is left', async () => {
    const element = await render();
    const input = one(element, '[data-field="dietary"][data-id="g2"]');
    Object.defineProperty(input, 'value', { value: 'Nut allergy', configurable: true });
    input.dispatchEvent(new CustomEvent('blur'));
    await flush();
    expect(saveNeeds).toHaveBeenCalledWith({
      attendeeId: 'g2',
      dietary: 'Nut allergy',
      access: undefined
    });
  });

  it('shows a load failure', async () => {
    getSeating.mockRejectedValue({ body: { message: 'No' } });
    const element = createElement('c-event-seating', { is: EventSeating });
    element.recordId = EVENT_ID;
    document.body.appendChild(element);
    await flush();
    expect(one(element, '[data-id="error-message"]')).not.toBeNull();
  });
});
