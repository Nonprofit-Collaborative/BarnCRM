import {
  dayKey,
  entriesByDay,
  entriesFrom,
  filterEntries,
  firstDayFrom,
  icsFileName,
  icsFold,
  icsFor,
  icsMoment,
  icsText,
  listDays,
  monthRange,
  monthWeeks,
  shiftAnchor,
  viewRange,
  weekDays,
  weekRange,
  weekdayOrder
} from '../eventCalendarModel';

const CALENDAR = {
  events: [
    {
      id: 'e1',
      name: 'Community Dreamin',
      status: 'Open',
      format: 'In Person',
      startsAt: '2027-06-03T16:00:00.000Z',
      endsAt: '2027-06-05T01:00:00.000Z',
      venueName: 'Town Hall',
      venueAddress: '1 Main St, Springfield',
      description: 'Two days; bring friends.'
    },
    {
      id: 'e2',
      name: 'Webinar',
      status: 'Cancelled',
      format: 'Virtual',
      startsAt: '2027-06-10T14:00:00.000Z',
      endsAt: '2027-06-10T15:00:00.000Z',
      onlineLink: 'https://example.org/join'
    }
  ],
  sessions: [
    {
      id: 's1',
      name: 'Opening Keynote',
      status: 'Confirmed',
      sessionType: 'Keynote',
      room: 'Hall A',
      startsAt: '2027-06-03T17:00:00.000Z',
      endsAt: '2027-06-03T18:00:00.000Z',
      eventId: 'e1',
      eventName: 'Community Dreamin',
      eventStatus: 'Open',
      eventFormat: 'In Person'
    }
  ]
};

describe('eventCalendarModel dates', () => {
  it('finds the day in the person time zone, not UTC', () => {
    expect(dayKey('2027-06-05T01:00:00.000Z', 'UTC')).toBe('2027-06-05');
    expect(dayKey('2027-06-05T01:00:00.000Z', 'America/New_York')).toBe('2027-06-04');
    expect(dayKey('nonsense')).toBe('');
    expect(dayKey(null)).toBe('');
  });

  it('shows whole weeks around a month, starting on the chosen day', () => {
    expect(monthRange(2027, 6, 0)).toEqual({ from: '2027-05-30', to: '2027-07-03' });
    expect(monthRange(2027, 6, 1)).toEqual({ from: '2027-05-31', to: '2027-07-04' });
  });

  it('works out each view range and moves a step', () => {
    expect(weekRange('2027-06-09', 0)).toEqual({ from: '2027-06-06', to: '2027-06-12' });
    expect(viewRange('week', '2027-06-09', 1)).toEqual({ from: '2027-06-07', to: '2027-06-13' });
    expect(viewRange('list', '2027-06-09')).toEqual({ from: '2027-06-01', to: '2027-06-30' });
    expect(viewRange('month', '2027-06-09')).toEqual({ from: '2027-05-30', to: '2027-07-03' });
    expect(shiftAnchor('week', '2027-06-09', -1)).toBe('2027-06-02');
    expect(shiftAnchor('month', '2027-12-15', 1)).toBe('2028-01-01');
    expect(shiftAnchor('list', '2027-01-20', -1)).toBe('2026-12-01');
  });

  it('reads Salesforce first day of week and orders weekdays', () => {
    expect(firstDayFrom('1')).toBe(0);
    expect(firstDayFrom(2)).toBe(1);
    expect(firstDayFrom(undefined)).toBe(0);
    expect(weekdayOrder(1)).toEqual([1, 2, 3, 4, 5, 6, 0]);
  });
});

describe('eventCalendarModel entries', () => {
  const entries = entriesFrom(CALENDAR, 'UTC');

  it('builds entries sorted by start with the place', () => {
    expect(entries.map((entry) => entry.key)).toEqual(['event-e1', 'session-s1', 'event-e2']);
    expect(entries[0].place).toBe('Town Hall, 1 Main St, Springfield');
    expect(entries[2].place).toBe('https://example.org/join');
    expect(entries[1]).toMatchObject({ kind: 'session', place: 'Hall A', typeLabel: 'Keynote' });
    expect(entries[0]).toMatchObject({ startDay: '2027-06-03', endDay: '2027-06-05' });
  });

  it('skips rows with no readable start and tolerates no calendar', () => {
    expect(entriesFrom({ events: [{ id: 'x', name: 'No date' }] }, 'UTC')).toEqual([]);
    expect(entriesFrom(undefined, 'UTC')).toEqual([]);
  });

  it('filters by status and format, a session through its event, and drops sessions', () => {
    expect(filterEntries(entries, { status: 'Cancelled' }).map((e) => e.key)).toEqual(['event-e2']);
    expect(filterEntries(entries, { format: 'In Person' }).map((e) => e.key)).toEqual([
      'event-e1',
      'session-s1'
    ]);
    expect(filterEntries(entries, { sessions: false }).map((e) => e.key)).toEqual([
      'event-e1',
      'event-e2'
    ]);
    expect(filterEntries(entries)).toHaveLength(3);
  });

  it('puts a multi-day event on every day it spans, clipped to the days shown', () => {
    const byDay = entriesByDay(entries, '2027-06-04', '2027-06-04');
    expect([...byDay.keys()]).toEqual(['2027-06-04']);
    expect(byDay.get('2027-06-04')[0]).toMatchObject({ continues: true, continuesAfter: true });
    const full = entriesByDay(entries, '2027-06-01', '2027-06-30');
    expect(
      [...full.keys()].filter((day) => full.get(day).some((e) => e.key === 'event-e1'))
    ).toEqual(['2027-06-03', '2027-06-04', '2027-06-05']);
    expect(full.get('2027-06-05')[0].continuesAfter).toBe(false);
  });

  it('lays a month into weeks of seven days with today and the month marked', () => {
    const weeks = monthWeeks(2027, 6, entries, '2027-06-03', 0);
    expect(weeks).toHaveLength(5);
    weeks.forEach((week) => expect(week.days).toHaveLength(7));
    const third = weeks[0].days.find((day) => day.date === '2027-06-03');
    expect(third.isToday).toBe(true);
    expect(third.items.map((item) => item.name)).toEqual(['Community Dreamin', 'Opening Keynote']);
    expect(weeks[0].days[0]).toMatchObject({ date: '2027-05-30', inMonth: false });
  });

  it('draws a week and a list of only the busy days', () => {
    const week = weekDays('2027-06-03', entries, '2027-06-03', 0);
    expect(week.map((day) => day.date)[0]).toBe('2027-05-30');
    expect(week).toHaveLength(7);
    const list = listDays('2027-06-01', '2027-06-30', entries, '2027-06-03');
    expect(list.map((day) => day.date)).toEqual([
      '2027-06-03',
      '2027-06-04',
      '2027-06-05',
      '2027-06-10'
    ]);
  });
});

describe('eventCalendarModel calendar file', () => {
  it('escapes text values and formats UTC moments', () => {
    expect(icsText('a, b; c\\d\ne')).toBe('a\\, b\\; c\\\\d\\ne');
    expect(icsText(null)).toBe('');
    expect(icsMoment('2027-06-04T08:00:00.000Z')).toBe('20270604T080000Z');
    expect(icsMoment('bad')).toBe('');
  });

  it('folds long lines at 75 octets without splitting a character', () => {
    const folded = icsFold(`SUMMARY:${'x'.repeat(200)}`);
    const octets = (line) => unescape(encodeURIComponent(line)).length;
    folded.split('\r\n').forEach((line) => {
      expect(octets(line)).toBeLessThanOrEqual(75);
    });
    expect(folded.replace(/\r\n /g, '')).toBe(`SUMMARY:${'x'.repeat(200)}`);
    const accents = icsFold('é'.repeat(100));
    accents.split('\r\n').forEach((line) => {
      expect(octets(line)).toBeLessThanOrEqual(75);
    });
    expect(accents.replace(/\r\n /g, '')).toBe('é'.repeat(100));
  });

  it('writes one VEVENT per entry with place, description, link and status', () => {
    const entries = entriesFrom(CALENDAR, 'UTC');
    const text = icsFor([entries[0], entries[2]], new Date('2027-01-01T00:00:00Z'));
    expect(text.startsWith('BEGIN:VCALENDAR\r\nVERSION:2.0\r\n')).toBe(true);
    expect(text.endsWith('END:VCALENDAR\r\n')).toBe(true);
    expect(text.match(/BEGIN:VEVENT/g)).toHaveLength(2);
    expect(text).toContain('UID:e1@barncrm');
    expect(text).toContain('DTSTAMP:20270101T000000Z');
    expect(text).toContain('DTSTART:20270603T160000Z');
    expect(text).toContain('DTEND:20270605T010000Z');
    expect(text).toContain('LOCATION:Town Hall\\, 1 Main St\\, Springfield');
    expect(text).toContain('DESCRIPTION:Two days\\; bring friends.');
    expect(text).toContain('STATUS:CONFIRMED');
    expect(text).toContain('STATUS:CANCELLED');
    expect(text).toContain('URL:https://example.org/join');
    expect(text.split('\r\n').every((line) => !line.includes('\n'))).toBe(true);
  });

  it('names a session after its event and marks a draft tentative', () => {
    const [, session] = entriesFrom(CALENDAR, 'UTC');
    const text = icsFor([{ ...session, status: 'Draft' }]);
    expect(text).toContain('SUMMARY:Opening Keynote (Community Dreamin)');
    expect(text).toContain('STATUS:TENTATIVE');
  });

  it('skips an entry with no start and makes a safe file name', () => {
    expect(icsFor([{ recordId: 'x', name: 'No start' }])).not.toContain('VEVENT');
    expect(icsFileName({ name: 'Community Dreamin: Day 1!' })).toBe('community-dreamin-day-1.ics');
    expect(icsFileName({ name: '' })).toBe('event.ics');
    expect(icsFileName(undefined)).toBe('event.ics');
  });
});
