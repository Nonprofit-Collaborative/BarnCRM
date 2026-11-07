import { createElement } from 'lwc';
import EventCheckIn from 'c/eventCheckIn';
import getCheckIn from '@salesforce/apex/EventCheckInController.getCheckIn';
import checkIn from '@salesforce/apex/EventCheckInController.checkIn';
import walkIn from '@salesforce/apex/EventCheckInController.walkIn';

jest.mock('@salesforce/apex/EventCheckInController.getCheckIn', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/EventCheckInController.checkIn', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/EventCheckInController.walkIn', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/resourceUrl/BarnQrCode', () => ({ default: 'qr.js' }), {
  virtual: true
});

const EVENT_ID = 'a01000000000001AAA';
const JANE = 'a09000000000001AAA';
const MAX = 'a09000000000002AAA';
const DATA = {
  canCheckIn: true,
  canWalkIn: true,
  truncated: false,
  tickets: [{ value: 't1', label: 'General' }],
  attendees: [
    {
      id: JANE,
      name: 'Jane Doe',
      email: 'jane@example.org',
      ticketName: 'General',
      status: 'Registered'
    },
    { id: MAX, name: 'Max Roe', ticketName: 'General', status: 'Attended' }
  ]
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(data = DATA) {
  getCheckIn.mockResolvedValue(data);
  const element = createElement('c-event-check-in', { is: EventCheckIn });
  element.recordId = EVENT_ID;
  document.body.appendChild(element);
  await flush();
  return element;
}

const all = (element, selector) => [...element.shadowRoot.querySelectorAll(selector)];
const one = (element, selector) => element.shadowRoot.querySelector(selector);
const type = (input, value) =>
  input.dispatchEvent(new CustomEvent('change', { detail: { value } }));

describe('c-event-check-in', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    delete window.qrcode;
  });

  it('lists the people holding a seat with the count in', async () => {
    const element = await render();
    expect(getCheckIn).toHaveBeenCalledWith({ eventId: EVENT_ID });
    expect(all(element, '[data-id="attendee-row"]')).toHaveLength(2);
    expect(one(element, '[data-id="summary"]')).not.toBeNull();
  });

  it('shows the empty state when nobody holds a seat', async () => {
    const element = await render({ ...DATA, attendees: [] });
    expect(one(element, '[data-id="empty-state"]')).not.toBeNull();
  });

  it('narrows the list as the staff member types', async () => {
    const element = await render();
    type(one(element, '[data-id="search"]'), 'max');
    await flush();
    expect(all(element, '[data-id="attendee-row"]')).toHaveLength(1);
    type(one(element, '[data-id="search"]'), 'zzz');
    await flush();
    expect(one(element, '[data-id="no-match"]')).not.toBeNull();
  });

  it('checks a person in with one click and undoes a check-in', async () => {
    const element = await render();
    checkIn.mockResolvedValue('Attended');
    all(element, '[data-action="toggle"]')[0].click();
    await flush();
    expect(checkIn).toHaveBeenCalledWith({ attendeeId: JANE, undo: false });
    all(element, '[data-action="toggle"]')[1].click();
    await flush();
    expect(checkIn).toHaveBeenCalledWith({ attendeeId: MAX, undo: true });
    expect(getCheckIn).toHaveBeenCalledTimes(3);
  });

  it('checks in by a typed code and refuses a code from another event', async () => {
    const element = await render();
    checkIn.mockResolvedValue('Attended');
    type(one(element, '[data-id="code"]'), JANE);
    one(element, '[data-id="code-submit"]').click();
    await flush();
    expect(checkIn).toHaveBeenCalledWith({ attendeeId: JANE, undo: false });
    checkIn.mockClear();
    type(one(element, '[data-id="code"]'), 'a09000000000009AAA');
    one(element, '[data-id="code-submit"]').click();
    await flush();
    expect(checkIn).not.toHaveBeenCalled();
  });

  it('does not check in someone already in', async () => {
    const element = await render();
    type(one(element, '[data-id="code"]'), MAX);
    one(element, '[data-id="code-submit"]').click();
    await flush();
    expect(checkIn).not.toHaveBeenCalled();
  });

  it('hides check-in and walk-in controls from a person who cannot change', async () => {
    const element = await render({ ...DATA, canCheckIn: false, canWalkIn: false });
    expect(all(element, '[data-action="toggle"]')).toHaveLength(0);
    expect(one(element, '[data-id="walk-in"]')).toBeNull();
    expect(one(element, '[data-id="code"]')).toBeNull();
  });

  it('offers no camera button when the browser cannot read codes', async () => {
    const element = await render();
    expect(one(element, '[data-id="scan"]')).toBeNull();
    expect(one(element, '[data-id="camera-help"]')).not.toBeNull();
  });

  it('adds a walk-in', async () => {
    const element = await render();
    walkIn.mockResolvedValue({ registered: 1 });
    one(element, '[data-id="walk-in"]').click();
    await flush();
    expect(one(element, '[data-id="walk-in-add"]').disabled).toBe(true);
    type(one(element, '[data-field="lastName"]'), 'Door');
    await flush();
    one(element, '[data-id="walk-in-add"]').click();
    await flush();
    const sent = JSON.parse(walkIn.mock.calls[0][0].requestJson);
    expect(sent.eventId).toBe(EVENT_ID);
    expect(sent.registrant.lastName).toBe('Door');
    expect(sent.ticketType).toBe('t1');
    expect(getCheckIn).toHaveBeenCalledTimes(2);
  });

  it('draws and closes an attendee QR code made in the browser', async () => {
    const added = [];
    window.qrcode = () => ({
      addData: (text) => added.push(text),
      make: () => {},
      createDataURL: () => 'data:image/gif;base64,AAAA'
    });
    const element = await render();
    all(element, '[data-action="qr"]')[0].click();
    await flush();
    expect(added).toEqual([JANE]);
    expect(one(element, '[data-id="qr-image"]').src).toContain('data:image/gif');
    one(element, '[data-id="qr-close"]').click();
    await flush();
    expect(one(element, '[data-id="qr-panel"]')).toBeNull();
  });
});
