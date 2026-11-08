import { createElement } from 'lwc';
import EventCalendar from 'c/eventCalendar';
import getCalendar from '@salesforce/apex/EventCalendarController.getCalendar';

const mockNavigate = jest.fn();
jest.mock(
  'lightning/navigation',
  () => {
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) =>
      class extends Base {
        [Navigate](...args) {
          mockNavigate(...args);
        }
      };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin, CurrentPageReference: null, __esModule: true };
  },
  { virtual: true }
);
jest.mock('@salesforce/apex/EventCalendarController.getCalendar', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/i18n/locale', () => ({ default: 'en-US' }), { virtual: true });
jest.mock('@salesforce/i18n/timeZone', () => ({ default: 'UTC' }), { virtual: true });
jest.mock('@salesforce/i18n/firstDayOfWeek', () => ({ default: 1 }), { virtual: true });
jest.mock('@salesforce/label/c.Core_Address_DateRange', () => ({ default: '{0} to {1}' }), {
  virtual: true
});

const NOW = new Date();
const day = (dayOfMonth, hour) =>
  new Date(Date.UTC(NOW.getUTCFullYear(), NOW.getUTCMonth(), dayOfMonth, hour)).toISOString();
const TODAY = NOW.toISOString().slice(0, 10);

const CALENDAR = {
  today: TODAY,
  truncated: false,
  events: [
    {
      id: 'a01000000000001AAA',
      name: 'Spring Gala',
      status: 'Open',
      format: 'In Person',
      startsAt: day(15, 18),
      endsAt: day(15, 21),
      venueName: 'Town Hall'
    },
    {
      id: 'a01000000000002AAA',
      name: 'Donor Webinar',
      status: 'Cancelled',
      format: 'Virtual',
      startsAt: day(16, 14),
      endsAt: day(16, 15),
      onlineLink: 'https://example.org/join'
    }
  ],
  sessions: []
};

const SESSIONS = {
  ...CALENDAR,
  sessions: [
    {
      id: 'a05000000000001AAA',
      name: 'Opening Keynote',
      status: 'Confirmed',
      sessionType: 'Keynote',
      room: 'Hall A',
      startsAt: day(15, 18),
      endsAt: day(15, 19),
      eventId: 'a01000000000001AAA',
      eventName: 'Spring Gala',
      eventStatus: 'Open',
      eventFormat: 'In Person'
    }
  ]
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(calendar = CALENDAR) {
  getCalendar.mockResolvedValue(calendar);
  const element = createElement('c-event-calendar', { is: EventCalendar });
  document.body.appendChild(element);
  await flush();
  return element;
}

const one = (element, selector) => element.shadowRoot.querySelector(selector);
const all = (element, selector) => [...element.shadowRoot.querySelectorAll(selector)];
const names = (element) => all(element, '[data-id="item"]').map((item) => item.textContent.trim());

describe('c-event-calendar', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('draws the month with the events and asks for whole weeks without sessions', async () => {
    const element = await render();
    expect(getCalendar).toHaveBeenCalledTimes(1);
    const args = getCalendar.mock.calls[0][0];
    expect(args.includeSessions).toBe(false);
    expect(args.fromDate <= TODAY && TODAY <= args.toDate).toBe(true);
    expect(all(element, '[data-id="week"]').length).toBeGreaterThanOrEqual(4);
    expect(names(element)).toEqual(['Spring Gala', 'Donor Webinar']);
  });

  it('filters by status in the browser without reading again', async () => {
    const element = await render();
    one(element, '[data-id="status"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Cancelled' } })
    );
    await flush();
    expect(names(element)).toEqual(['Donor Webinar']);
    one(element, '[data-id="status"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'all' } })
    );
    one(element, '[data-id="format"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'In Person' } })
    );
    await flush();
    expect(names(element)).toEqual(['Spring Gala']);
    expect(getCalendar).toHaveBeenCalledTimes(1);
  });

  it('reads sessions only when Show Sessions is on', async () => {
    const element = await render(SESSIONS);
    expect(names(element)).toEqual(['Spring Gala', 'Donor Webinar']);
    const toggle = one(element, '[data-id="sessions"]');
    toggle.dispatchEvent(new CustomEvent('change', { detail: { checked: true } }));
    await flush();
    expect(getCalendar).toHaveBeenCalledTimes(2);
    expect(getCalendar.mock.calls[1][0].includeSessions).toBe(true);
    expect(names(element).some((text) => text.startsWith('Opening Keynote'))).toBe(true);
  });

  it('moves a month and back to today, reading each time', async () => {
    const element = await render();
    one(element, '[data-id="next"]').click();
    await flush();
    one(element, '[data-id="today"]').click();
    await flush();
    expect(getCalendar).toHaveBeenCalledTimes(3);
    expect(getCalendar.mock.calls[1][0].fromDate).not.toBe(getCalendar.mock.calls[0][0].fromDate);
    expect(getCalendar.mock.calls[2][0].fromDate).toBe(getCalendar.mock.calls[0][0].fromDate);
  });

  it('shows the week view and the list view', async () => {
    const element = await render();
    one(element, '[data-id="view"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'week' } })
    );
    await flush();
    expect(one(element, '[data-id="week-view"]')).not.toBeNull();
    expect(getCalendar.mock.calls[1][0].toDate > getCalendar.mock.calls[1][0].fromDate).toBe(true);
    one(element, '[data-id="view"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'list' } })
    );
    await flush();
    expect(one(element, '[data-id="week-view"]')).toBeNull();
    expect(all(element, '[data-id="list-item"]')).toHaveLength(2);
    expect(all(element, '[data-id="download"]')).toHaveLength(2);
  });

  it('opens the record when an entry is clicked', async () => {
    const element = await render();
    one(element, '[data-id="item"]').click();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__recordPage',
      attributes: {
        recordId: 'a01000000000001AAA',
        objectApiName: 'Event__c',
        actionName: 'view'
      }
    });
  });

  it('downloads a calendar file built in the browser for the chosen entry', async () => {
    const element = await render();
    one(element, '[data-id="view"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'list' } })
    );
    await flush();
    let blob;
    global.URL.createObjectURL = jest.fn((made) => {
      blob = made;
      return 'blob:test';
    });
    global.URL.revokeObjectURL = jest.fn();
    const clicks = [];
    const realClick = HTMLAnchorElement.prototype.click;
    HTMLAnchorElement.prototype.click = function recordClick() {
      clicks.push(this.download);
    };
    try {
      one(element, '[data-id="download"]').click();
    } finally {
      HTMLAnchorElement.prototype.click = realClick;
    }
    expect(clicks).toEqual(['spring-gala.ics']);
    expect(blob.type).toContain('text/calendar');
    expect(global.URL.revokeObjectURL).toHaveBeenCalledWith('blob:test');
  });

  it('shows an empty state and an error in plain words', async () => {
    const empty = await render({ today: TODAY, events: [], sessions: [] });
    expect(one(empty, '[data-id="empty-state"]')).not.toBeNull();
    getCalendar.mockRejectedValue({ body: { message: 'Nope' } });
    const failing = createElement('c-event-calendar', { is: EventCalendar });
    document.body.appendChild(failing);
    await flush();
    expect(one(failing, '[data-id="error-message"]')).not.toBeNull();
  });
});
