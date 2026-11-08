import { createElement } from 'lwc';
import EventVolunteers from 'c/eventVolunteers';
import getVolunteers from '@salesforce/apex/EventVolunteersController.getVolunteers';
import addJob from '@salesforce/apex/EventVolunteersController.addJob';
import addShift from '@salesforce/apex/EventVolunteersController.addShift';

jest.mock(
  '@salesforce/apex/EventVolunteersController.getVolunteers',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/EventVolunteersController.addJob', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/EventVolunteersController.addShift', () => ({ default: jest.fn() }), {
  virtual: true
});

const EVENT_ID = 'a01000000000001AAA';
const JOB_ID = 'a0V000000000001AAA';
const DATA = {
  available: true,
  eventStart: '2027-06-04T08:00:00.000Z',
  eventEnd: '2027-06-04T18:00:00.000Z',
  jobs: [
    {
      id: JOB_ID,
      name: 'Registration Desk',
      active: true,
      href: `/lightning/r/${JOB_ID}/view`,
      shifts: [
        {
          id: 's1',
          startTime: '2027-06-04T08:00:00.000Z',
          endTime: '2027-06-04T12:00:00.000Z',
          needed: 3,
          filled: 1,
          status: 'Open'
        }
      ]
    }
  ]
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(data = DATA) {
  getVolunteers.mockResolvedValue(data);
  const element = createElement('c-event-volunteers', { is: EventVolunteers });
  element.recordId = EVENT_ID;
  document.body.appendChild(element);
  await flush();
  return element;
}

const one = (element, selector) => element.shadowRoot.querySelector(selector);
const all = (element, selector) => [...element.shadowRoot.querySelectorAll(selector)];

describe('c-event-volunteers', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('draws nothing at all when no module keeps volunteer jobs', async () => {
    const element = await render({ available: false, jobs: [] });
    expect(one(element, '[data-id="volunteers"]')).toBeNull();
  });

  it('lists jobs with their shifts and how full each is', async () => {
    const element = await render();
    expect(getVolunteers).toHaveBeenCalledWith({ eventId: EVENT_ID });
    expect(all(element, '[data-id="job"]')).toHaveLength(1);
    expect(all(element, '[data-id="shift"]')).toHaveLength(1);
    expect(one(element, '[data-id="shift"] c-barn-status-badge').status).toBe('pending');
    expect(one(element, '[data-id="summary"]')).not.toBeNull();
  });

  it('shows the empty state when the event has no jobs', async () => {
    const element = await render({ ...DATA, jobs: [] });
    expect(one(element, '[data-id="empty-state"]')).not.toBeNull();
  });

  it('adds a job for the event by name', async () => {
    const element = await render();
    expect(one(element, '[data-id="add-job"]').disabled).toBe(true);
    one(element, '[data-id="job-name"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'AV Help' } })
    );
    await flush();
    addJob.mockResolvedValue('a0V000000000002AAA');
    one(element, '[data-id="add-job"]').click();
    await flush();
    expect(addJob).toHaveBeenCalledWith({ eventId: EVENT_ID, name: 'AV Help', description: null });
    expect(getVolunteers).toHaveBeenCalledTimes(2);
  });

  it('opens a shift form with the event first hour and saves it', async () => {
    const element = await render();
    one(element, '[data-action="open-shift"]').click();
    await flush();
    expect(one(element, '[data-id="shift-form"]')).not.toBeNull();
    expect(one(element, '[data-id="shift-start"]').value).toBe('2027-06-04T08:00:00.000Z');
    addShift.mockResolvedValue('s2');
    one(element, '[data-id="shift-save"]').click();
    await flush();
    expect(addShift).toHaveBeenCalledWith({
      eventId: EVENT_ID,
      jobId: JOB_ID,
      startTime: '2027-06-04T08:00:00.000Z',
      endTime: '2027-06-04T09:00:00.000Z',
      needed: 2
    });
    expect(one(element, '[data-id="shift-form"]')).toBeNull();
  });

  it('blocks a shift with no volunteers asked for, but only warns outside the event dates', async () => {
    const element = await render();
    one(element, '[data-action="open-shift"]').click();
    await flush();
    one(element, '[data-id="shift-needed"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: '0' } })
    );
    await flush();
    expect(one(element, '[data-id="shift-save"]').disabled).toBe(true);
    one(element, '[data-id="shift-needed"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: '2' } })
    );
    one(element, '[data-id="shift-start"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: '2027-06-03T20:00:00.000Z' } })
    );
    await flush();
    expect(one(element, '[data-id="shift-save"]').disabled).toBe(false);
    expect(addShift).not.toHaveBeenCalled();
  });

  it('shows the load error', async () => {
    getVolunteers.mockRejectedValue({ body: { message: 'Broken' } });
    const element = createElement('c-event-volunteers', { is: EventVolunteers });
    element.recordId = EVENT_ID;
    document.body.appendChild(element);
    await flush();
    expect(one(element, '[data-id="error-message"]')).not.toBeNull();
  });
});
