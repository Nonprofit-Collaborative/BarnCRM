import {
  canTakeTemplate,
  daysToGo,
  parseTemplates,
  planFromTemplate,
  setupSteps,
  timelineFor
} from 'c/eventDashboardModel';

const NOW = new Date(2027, 2, 10, 15, 0);
const TEMPLATE = {
  key: 'conference',
  name: 'Conference',
  tracks: [{ name: 'Admins' }, { name: 'Developers', sortOrder: 5 }],
  ticketTypes: [
    { name: 'Attendee', price: 25 },
    { name: 'Speaker', quantity: 10 }
  ],
  sessions: [
    { name: 'Keynote', type: 'Keynote', day: 1, start: '09:00', end: '10:00' },
    { name: 'Talk', day: 2, start: '10:00', end: '11:00', track: 'Admins', room: 'A' },
    { name: 'Late', day: 3, start: '10:00', end: '11:00' }
  ],
  timeline: [
    { title: 'Remind', daysBefore: 7 },
    { title: 'Call', daysBefore: 100 },
    { title: 'Doors', daysBefore: 0 }
  ]
};

describe('eventDashboardModel', () => {
  it('counts whole days to the start, past start negative', () => {
    expect(daysToGo(new Date(2027, 2, 20, 9, 0), NOW)).toBe(10);
    expect(daysToGo(new Date(2027, 2, 10, 23, 0), NOW)).toBe(0);
    expect(daysToGo(new Date(2027, 2, 8, 9, 0), NOW)).toBe(-2);
    expect(daysToGo(null, NOW)).toBeNull();
  });

  it('marks a setup step done once the event has its records', () => {
    expect(setupSteps({ ticketTypes: 1, sessions: 0, speakers: 2 }).map((s) => s.done)).toEqual([
      true,
      false,
      true
    ]);
    expect(setupSteps(null).every((s) => !s.done)).toBe(true);
  });

  it('only offers a template to an event that is still empty', () => {
    expect(canTakeTemplate({ ticketTypes: 0, tracks: 0, sessions: 0, speakers: 3 })).toBe(true);
    expect(canTakeTemplate({ ticketTypes: 0, tracks: 1, sessions: 0 })).toBe(false);
  });

  it('reads templates, and none from damaged text', () => {
    expect(parseTemplates(JSON.stringify({ templates: [TEMPLATE, { x: 1 }] }))).toHaveLength(1);
    expect(parseTemplates('not json')).toEqual([]);
    expect(parseTemplates('{}')).toEqual([]);
  });

  it('turns a template into a plan with dated sessions and drops those past the end', () => {
    const start = new Date(2027, 5, 4, 8, 0);
    const end = new Date(2027, 5, 5, 18, 0);
    const plan = planFromTemplate(TEMPLATE, start, end);
    expect(plan.tracks).toEqual([
      { name: 'Admins', sortOrder: 1 },
      { name: 'Developers', sortOrder: 5 }
    ]);
    expect(plan.ticketTypes[0]).toEqual({
      name: 'Attendee',
      price: 25,
      quantity: null,
      sortOrder: 1
    });
    expect(plan.ticketTypes[1].price).toBe(0);
    expect(plan.ticketTypes[1].quantity).toBe(10);
    expect(plan.sessions).toHaveLength(2);
    expect(plan.skipped).toBe(1);
    expect(new Date(plan.sessions[0].startTime)).toEqual(new Date(2027, 5, 4, 9, 0));
    expect(new Date(plan.sessions[1].startTime)).toEqual(new Date(2027, 5, 5, 10, 0));
    expect(plan.sessions[1].trackName).toBe('Admins');
    expect(plan.sessions[1].room).toBe('A');
  });

  it('drops a session that starts before the event does', () => {
    const plan = planFromTemplate(TEMPLATE, new Date(2027, 5, 4, 9, 30), null);
    expect(plan.sessions.map((s) => s.name)).toEqual(['Talk', 'Late']);
    expect(planFromTemplate(null, new Date()).sessions).toEqual([]);
  });

  it('orders the timeline by due date and grades each step', () => {
    const start = new Date(2027, 2, 15, 9, 0);
    const steps = timelineFor(TEMPLATE, start, NOW);
    expect(steps.map((s) => s.title)).toEqual(['Call', 'Remind', 'Doors']);
    expect(steps.map((s) => s.state)).toEqual(['past', 'past', 'soon']);
    expect(timelineFor(TEMPLATE, null, NOW)).toEqual([]);
    const far = timelineFor(TEMPLATE, new Date(2028, 2, 15), NOW);
    expect(far.find((s) => s.title === 'Doors').state).toBe('later');
  });
});
