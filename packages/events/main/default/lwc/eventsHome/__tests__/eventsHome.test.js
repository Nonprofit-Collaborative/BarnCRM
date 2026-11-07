import { createElement } from 'lwc';
import EventsHome from 'c/eventsHome';
import getEvents from '@salesforce/apex/EventsHomeController.getEvents';
import repeatEvent from '@salesforce/apex/EventsHomeController.repeatEvent';
import EventRepeatModal from 'c/eventRepeatModal';

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
jest.mock('@salesforce/apex/EventsHomeController.getEvents', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/EventsHomeController.repeatEvent', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/i18n/locale', () => ({ default: 'en-US' }), { virtual: true });
jest.mock('@salesforce/i18n/timeZone', () => ({ default: 'UTC' }), { virtual: true });
jest.mock('@salesforce/label/c.Core_Address_DateRange', () => ({ default: '{0} to {1}' }), {
  virtual: true
});

const HOME = {
  title: 'Events',
  canCreate: true,
  truncated: false,
  fieldLabels: {
    Name: 'Event Name',
    Status__c: 'Status',
    Format__c: 'Format',
    Capacity__c: 'Capacity'
  },
  events: [
    {
      id: 'a01000000000001AAA',
      name: 'Spring Gala',
      status: 'Open',
      format: 'In Person',
      startsAt: '2026-03-07T18:00:00.000Z',
      endsAt: '2026-03-07T22:00:00.000Z',
      venueName: 'Town Hall',
      capacity: 200
    },
    {
      id: 'a01000000000002AAA',
      name: 'Admin Webinar',
      status: 'Draft',
      format: 'Virtual',
      startsAt: '2026-04-01T15:00:00.000Z',
      endsAt: '2026-04-01T16:00:00.000Z',
      onlineLink: 'https://example.org/join'
    }
  ]
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(home = HOME) {
  getEvents.mockResolvedValue(home);
  const element = createElement('c-events-home', { is: EventsHome });
  document.body.appendChild(element);
  await flush();
  await flush();
  return element;
}

const all = (element, selector) => [...element.shadowRoot.querySelectorAll(selector)];
const one = (element, selector) => element.shadowRoot.querySelector(selector);

describe('c-events-home', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists the upcoming events with their dates, status and place', async () => {
    const element = await render();
    expect(getEvents).toHaveBeenCalledWith({ view: 'upcoming' });
    const rows = all(element, '[data-id="event-row"]');
    expect(rows).toHaveLength(2);
    expect(rows[0].textContent).toContain('Sat, Mar 7, 2026, 6:00 PM');
    expect(rows[0].textContent).toContain('Town Hall');
    expect(rows[1].textContent).toContain('c.Events_Home_Online');
    const badge = rows[0].querySelector('c-barn-status-badge');
    expect(badge.status).toBe('active');
  });

  it('switches to the past events', async () => {
    const element = await render();
    const view = one(element, '[data-id="view"]');
    view.dispatchEvent(new CustomEvent('change', { detail: { value: 'past' } }));
    await flush();
    expect(getEvents).toHaveBeenLastCalledWith({ view: 'past' });
  });

  it('shows an empty state with New Event when nothing is coming up', async () => {
    const element = await render({ ...HOME, events: [] });
    expect(one(element, '[data-id="empty-state"]')).not.toBeNull();
    one(element, '[data-id="empty-new-event"]').click();
    expect(mockNavigate).toHaveBeenCalledWith(
      expect.objectContaining({ attributes: { objectApiName: 'Event__c', actionName: 'new' } })
    );
  });

  it('offers no New Event or Repeat Event to a reader', async () => {
    const element = await render({ ...HOME, canCreate: false });
    expect(one(element, '[data-id="new-event"]')).toBeNull();
    const items = all(element, 'lightning-menu-item').map((item) => item.value);
    expect(items).toEqual(['open', 'open']);
  });

  it('repeats an event with the dates the dialog chose and reloads', async () => {
    EventRepeatModal.open.mockResolvedValue({ starts: ['2026-03-14T18:00:00.000Z'] });
    repeatEvent.mockResolvedValue(1);
    const element = await render();
    const menu = one(element, 'lightning-button-menu');
    menu.dispatchEvent(new CustomEvent('select', { detail: { value: 'repeat' } }));
    await flush();
    await flush();
    expect(EventRepeatModal.open).toHaveBeenCalledWith(
      expect.objectContaining({ eventName: 'Spring Gala', startsAt: '2026-03-07T18:00:00.000Z' })
    );
    expect(repeatEvent).toHaveBeenCalledWith({
      eventId: 'a01000000000001AAA',
      starts: ['2026-03-14T18:00:00.000Z']
    });
    expect(getEvents).toHaveBeenCalledTimes(2);
  });

  it('saves nothing when the dialog is closed', async () => {
    EventRepeatModal.open.mockResolvedValue(undefined);
    const element = await render();
    one(element, 'lightning-button-menu').dispatchEvent(
      new CustomEvent('select', { detail: { value: 'repeat' } })
    );
    await flush();
    expect(repeatEvent).not.toHaveBeenCalled();
  });

  it('shows the reason when the list cannot load', async () => {
    getEvents.mockRejectedValue({ body: { message: 'No access' } });
    const element = createElement('c-events-home', { is: EventsHome });
    document.body.appendChild(element);
    await flush();
    await flush();
    expect(one(element, '[data-id="error-message"]').message).toBe('No access');
  });
});
