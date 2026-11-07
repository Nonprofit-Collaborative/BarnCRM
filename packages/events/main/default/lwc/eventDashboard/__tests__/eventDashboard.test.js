import { createElement } from 'lwc';
import EventDashboard from 'c/eventDashboard';
import getDashboard from '@salesforce/apex/EventDashboardController.getDashboard';
import applyPlan from '@salesforce/apex/EventDashboardController.applyPlan';

jest.mock(
  '@salesforce/apex/EventDashboardController.getDashboard',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/EventDashboardController.applyPlan', () => ({ default: jest.fn() }), {
  virtual: true
});

const EVENT_ID = 'a01000000000001AAA';
const TEMPLATES = JSON.stringify({
  templates: [
    {
      key: 'conference',
      name: 'Community Conference',
      description: 'Two days.',
      tracks: [{ name: 'Admins' }],
      ticketTypes: [{ name: 'Attendee', price: 25 }],
      sessions: [{ name: 'Keynote', type: 'Keynote', day: 1, start: '09:00', end: '10:00' }],
      timeline: [{ title: 'Open the call for speakers', daysBefore: 100 }]
    }
  ]
});

function dataWith(extra = {}) {
  const start = new Date();
  start.setDate(start.getDate() + 30);
  start.setHours(8, 0, 0, 0);
  const end = new Date(start);
  end.setDate(end.getDate() + 1);
  end.setHours(18, 0, 0, 0);
  return {
    eventStatus: 'Open',
    startsAt: start.toISOString(),
    endsAt: end.toISOString(),
    ticketTypes: 0,
    promoCodes: 0,
    tracks: 0,
    sessions: 0,
    speakers: 0,
    confirmedSpeakers: 0,
    templatesJson: TEMPLATES,
    canApplyTemplate: true,
    ...extra
  };
}

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(data) {
  getDashboard.mockResolvedValue(data);
  const element = createElement('c-event-dashboard', { is: EventDashboard });
  element.recordId = EVENT_ID;
  document.body.appendChild(element);
  await flush();
  return element;
}

const one = (element, selector) => element.shadowRoot.querySelector(selector);
const all = (element, selector) => [...element.shadowRoot.querySelectorAll(selector)];

describe('c-event-dashboard', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows the counts as tiles and the setup steps', async () => {
    const element = await render(dataWith({ sessions: 4, speakers: 2, confirmedSpeakers: 1 }));
    expect(getDashboard).toHaveBeenCalledWith({ eventId: EVENT_ID });
    expect(all(element, 'c-barn-stat-tile').map((t) => t.value)).toEqual([0, 0, 4, 2]);
    expect(all(element, '[data-id="steps"] c-barn-status-badge').map((b) => b.status)).toEqual([
      'pending',
      'active',
      'active'
    ]);
  });

  it('offers a template to an empty event and previews it without adding anything', async () => {
    const element = await render(dataWith());
    const picker = one(element, '[data-id="template"]');
    expect(picker.options).toEqual([{ label: 'Community Conference', value: 'conference' }]);
    expect(one(element, '[data-id="apply"]')).toBeNull();
    picker.dispatchEvent(new CustomEvent('change', { detail: { value: 'conference' } }));
    await flush();
    expect(all(element, '[data-id="timeline"] li')).toHaveLength(1);
    expect(one(element, '[data-id="apply"]')).not.toBeNull();
    expect(applyPlan).not.toHaveBeenCalled();
  });

  it('hides templates from an event that already has tracks, or from a person who cannot add', async () => {
    let element = await render(dataWith({ tracks: 1 }));
    expect(one(element, '[data-id="template"]')).toBeNull();
    document.body.removeChild(element);
    element = await render(dataWith({ canApplyTemplate: false }));
    expect(one(element, '[data-id="template"]')).toBeNull();
  });

  it('applies the chosen template as a dated plan and reloads', async () => {
    const element = await render(dataWith());
    applyPlan.mockResolvedValue(1);
    one(element, '[data-id="template"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'conference' } })
    );
    await flush();
    getDashboard.mockResolvedValue(dataWith({ tracks: 1, sessions: 1, ticketTypes: 1 }));
    one(element, '[data-id="apply"]').click();
    await flush();
    const call = applyPlan.mock.calls[0][0];
    expect(call.eventId).toBe(EVENT_ID);
    const plan = JSON.parse(call.planJson);
    expect(plan.tracks[0].name).toBe('Admins');
    expect(plan.sessions[0].startTime).toBeTruthy();
    expect(getDashboard).toHaveBeenCalledTimes(2);
    expect(one(element, '[data-id="template"]')).toBeNull();
  });

  it('shows the load error', async () => {
    getDashboard.mockRejectedValue({ body: { message: 'Broken' } });
    const element = createElement('c-event-dashboard', { is: EventDashboard });
    document.body.appendChild(element);
    await flush();
    expect(one(element, '[data-id="error-message"]')).not.toBeNull();
  });
});
