import {
  amountText,
  listView,
  nameTab,
  pageView,
  sitePageUrl,
  whenText
} from 'c/formPublicPageModel';

describe('nameTab', () => {
  it('sets the title, keeps it without a name, and is safe when the host refuses', () => {
    const doc = { title: 'Form' };
    expect(nameTab('Spring Gala', doc)).toBe(true);
    expect(doc.title).toBe('Spring Gala');
    expect(nameTab('', doc)).toBe(false);
    expect(doc.title).toBe('Spring Gala');
    const locked = {};
    Object.defineProperty(locked, 'title', {
      get: () => 'Form',
      set: () => {
        throw new Error('not allowed');
      }
    });
    expect(nameTab('Spring Gala', locked)).toBe(false);
    expect(locked.title).toBe('Form');
    expect(nameTab('Spring Gala', null)).toBe(false);
  });
});

const joiner = (start, end) => `${start} to ${end}`;

const PAGE = {
  kind: 'events',
  title: 'Spring Gala',
  description: 'An evening at the grange.',
  start: '2026-12-05T23:00:00.000Z',
  end: '2026-12-06T03:00:00.000Z',
  timeZone: 'America/New_York',
  facts: [{ label: 'Where', value: 'Grange Hall' }],
  sections: [
    {
      key: 'tickets',
      title: 'Tickets',
      items: [
        { title: 'General', amount: 50, currency: 'USD', note: 'Pay at the door.', badges: [] },
        { title: 'Student', badges: ['Free', 'Seats left: 3'], note: 'Ignored without a price' }
      ]
    }
  ],
  registration: 'Open',
  formId: 'a0B000000000001AAA',
  message: 'Register below.'
};

describe('c/formPublicPageModel', () => {
  it('formats a same-day event with the end as a time', () => {
    const when = whenText(PAGE.start, PAGE.end, PAGE.timeZone, 'en-US');
    expect(when.start).toContain('Dec 5, 2026');
    expect(when.start).toContain('6:00');
    expect(when.end).toBe('10:00 PM');
  });

  it('formats a multi-day event with both days, and nothing without a start', () => {
    const when = whenText('2026-12-05T15:00:00.000Z', '2026-12-07T15:00:00.000Z', 'UTC', 'en-US');
    expect(when.end).toContain('Dec 7, 2026');
    expect(whenText(null, null, 'UTC', 'en-US')).toEqual({ start: '', end: '' });
    expect(whenText('not a date', null, 'UTC', 'en-US').start).toBe('');
  });

  it('falls back to the browser time zone for an unknown one', () => {
    expect(whenText(PAGE.start, null, 'Not/AZone', 'en-US').start).not.toBe('');
  });

  it('formats an amount in its currency', () => {
    expect(amountText(50, 'USD', 'en-US')).toBe('$50.00');
    expect(amountText(null, 'USD', 'en-US')).toBe('');
    expect(amountText(5, '', 'en-US')).toBe('');
    expect(amountText('x', 'USD', 'en-US')).toBe('');
    expect(amountText(5, 'NOT-A-CURRENCY', 'en-US')).toBe('NOT-A-CURRENCY 5.00');
  });

  it('builds the page view with the form only while registration is open', () => {
    const view = pageView(PAGE, 'en-US', joiner);
    expect(view.title).toBe('Spring Gala');
    expect(view.when).toContain(' to 10:00 PM');
    expect(view.facts[0]).toEqual({ key: '0', label: 'Where', value: 'Grange Hall' });
    const [general, student] = view.sections[0].items;
    expect(general.price).toBe('$50.00');
    expect(general.note).toBe('Pay at the door.');
    expect(student.price).toBe('');
    expect(student.note).toBe('');
    expect(student.badges.map((badge) => badge.text)).toEqual(['Free', 'Seats left: 3']);
    expect(view.formId).toBe(PAGE.formId);

    expect(pageView({ ...PAGE, registration: 'Closed' }, 'en-US', joiner).formId).toBeNull();
    expect(pageView(null, 'en-US', joiner)).toBeNull();
    expect(pageView({}, 'en-US', joiner)).toBeNull();
  });

  it('builds the list with a link to each page', () => {
    const view = listView(
      {
        title: 'Upcoming Events',
        empty: 'None right now.',
        timeZone: 'UTC',
        items: [{ recordId: 'a01', title: 'Spring Gala', start: PAGE.start, subtitle: 'Grange' }]
      },
      'en-US',
      joiner,
      sitePageUrl
    );
    expect(view.items[0].href).toBe('?record=a01');
    expect(view.items[0].when).toContain('Dec 5, 2026');
    expect(listView(null, 'en-US', joiner, sitePageUrl)).toBeNull();
    expect(listView({}, 'en-US', joiner, sitePageUrl).items).toEqual([]);
  });
});
