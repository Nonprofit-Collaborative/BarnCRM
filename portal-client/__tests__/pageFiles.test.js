import { toCsv, toIcs } from '../src/pageFiles.js';

const PAGE = {
  calendar: { title: 'Name', start: 'Starts__c', end: 'Ends__c', location: 'Room__c' },
  fields: [
    { field: 'Name', label: 'Session' },
    { field: 'Starts__c', label: 'Starts' },
    { field: 'Room__c', label: 'Room' }
  ]
};

describe('toIcs', () => {
  it('makes one event per record with a title and start, escaped and in UTC', () => {
    const text = toIcs(
      PAGE,
      [
        {
          id: 'a01A',
          values: {
            Name: 'Keynote, then; coffee',
            Starts__c: '2026-11-20T15:00:00.000Z',
            Ends__c: '2026-11-20T16:00:00.000Z',
            Room__c: 'Hall A'
          }
        },
        { id: 'a01B', values: { Name: 'No start' } },
        { id: 'a01C', values: { Name: 'All day', Starts__c: '2026-11-21' } }
      ],
      new Date('2026-11-11T12:00:00Z')
    );
    expect(text.startsWith('BEGIN:VCALENDAR\r\n')).toBe(true);
    expect(text).toContain('SUMMARY:Keynote\\, then\\; coffee\r\n');
    expect(text).toContain('DTSTART:20261120T150000Z\r\n');
    expect(text).toContain('DTEND:20261120T160000Z\r\n');
    expect(text).toContain('LOCATION:Hall A\r\n');
    expect(text).toContain('DTSTART;VALUE=DATE:20261121\r\n');
    expect(text).toContain('DTSTAMP:20261111T120000Z\r\n');
    expect(text.match(/BEGIN:VEVENT/g)).toHaveLength(2);
    expect(text).not.toContain('No start');
  });

  it('folds long lines and returns nothing when no record can be an event', () => {
    const text = toIcs(PAGE, [
      { id: 'a01A', values: { Name: 'x'.repeat(100), Starts__c: '2026-11-21' } }
    ]);
    expect(text.split('\r\n').every((line) => line.length <= 75)).toBe(true);
    expect(toIcs(PAGE, [{ id: 'a01B', values: {} }])).toBe('');
  });
});

describe('toCsv', () => {
  it('labels the columns, quotes when needed and makes formulas inert', () => {
    const text = toCsv(
      PAGE,
      [
        { id: 'a01A', values: { Name: 'Say "hi", all', Starts__c: 'x', Room__c: '=1+1' } },
        { id: 'a01B', values: { Name: 'Plain' } }
      ],
      (field, value) => (value === undefined ? '' : String(value))
    );
    expect(text).toBe('Session,Starts,Room\r\n"Say ""hi"", all",x,\'=1+1\r\nPlain,,\r\n');
  });
});
