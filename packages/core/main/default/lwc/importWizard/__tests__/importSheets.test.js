import {
  defaultSheets,
  distinctHeaders,
  combineSheets,
  combineObjectSheets,
  exampleText,
  sheetConflicts,
  sheetsInLoadOrder,
  EXAMPLE_LENGTH
} from '../importSheets';

const IGNORE = '__ignore__';
const BLANK = '(blank)';

const people = {
  name: 'People',
  headers: ['First Name', 'Email'],
  records: [
    { 'First Name': 'Ana', Email: 'ana@example.org' },
    { 'First Name': 'Ben', Email: '' }
  ]
};
const more = {
  name: 'More',
  headers: ['Contact.First Name', 'Phone'],
  records: [{ 'Contact.First Name': 'Cy', Phone: '555 0100' }]
};
const empty = { name: 'Notes', headers: ['Note'], records: [] };

describe('importSheets', () => {
  it('chooses every sheet with rows, or the one sheet there is', () => {
    expect(defaultSheets([people, empty, more])).toEqual(['People', 'More']);
    expect(defaultSheets([empty])).toEqual(['Notes']);
    expect(defaultSheets([empty, { ...empty, name: 'Other' }])).toEqual(['Notes']);
  });

  it('lists each heading once, in first-seen order', () => {
    expect(distinctHeaders([people, { ...people, name: 'Again' }, more])).toEqual([
      'First Name',
      'Email',
      'Contact.First Name',
      'Phone'
    ]);
  });

  it('joins headings mapped to one field across sheets, and keeps the rest apart', () => {
    const { headers, records } = combineSheets(
      [people, more],
      [
        { 'First Name': 'Record.FirstName', Email: 'Record.Email' },
        { 'Contact.First Name': 'Record.FirstName', Phone: IGNORE }
      ],
      IGNORE,
      BLANK
    );
    expect(headers).toEqual(['First Name', 'Email', 'Phone']);
    expect(records).toEqual([
      { 'First Name': 'Ana', Email: 'ana@example.org', Phone: '' },
      { 'First Name': 'Ben', Email: '', Phone: '' },
      { 'First Name': 'Cy', Email: '', Phone: '555 0100' }
    ]);
  });

  it('never joins two Do not load columns, and one sheet passes through', () => {
    const ignored = combineSheets(
      [people, more],
      [{ 'First Name': IGNORE }, { 'Contact.First Name': IGNORE }],
      IGNORE
    );
    expect(ignored.headers).toEqual(['First Name', 'Email', 'Contact.First Name', 'Phone']);
    const single = combineSheets([people]);
    expect(single.headers).toEqual(people.headers);
    expect(single.records).toEqual(people.records);
  });

  it('gives each column its first values as examples, from the sheets that have it', () => {
    const { examples } = combineSheets(
      [people, more],
      [{ 'First Name': 'Record.FirstName' }, { 'Contact.First Name': 'Record.FirstName' }],
      IGNORE,
      BLANK
    );
    expect(examples['First Name']).toEqual(['Ana', 'Ben', 'Cy']);
    expect(examples.Email).toEqual(['ana@example.org', BLANK]);
    expect(examples.Phone).toEqual(['555 0100']);
  });

  it('stops at three examples and cuts a long value short', () => {
    const many = {
      name: '',
      headers: ['Notes'],
      records: ['a', 'b', 'c', 'd'].map((value) => ({ Notes: value }))
    };
    expect(combineSheets([many]).examples.Notes).toEqual(['a', 'b', 'c']);
    const long = 'x'.repeat(EXAMPLE_LENGTH + 10);
    expect(exampleText(long)).toHaveLength(EXAMPLE_LENGTH);
    expect(exampleText(long).endsWith('…')).toBe(true);
    expect(exampleText('<b>bold</b>')).toBe('<b>bold</b>');
    expect(exampleText(null, BLANK)).toBe(BLANK);
    expect(exampleText(0)).toBe('0');
  });

  it('names the sheets that point at different objects', () => {
    const objects = [
      { sheetName: 'People', objectName: 'Contact', objectLabel: 'Contact' },
      { sheetName: 'More', objectName: 'contact', objectLabel: 'Contact' },
      { sheetName: 'Shifts', objectName: 'Shift__c', objectLabel: 'Shift' },
      { sheetName: 'Notes', objectName: null, objectLabel: null }
    ];
    expect(sheetConflicts(['People', 'More', 'Notes'], objects, 'Contact')).toEqual([]);
    expect(sheetConflicts(['People', 'Shifts'], objects)).toEqual([objects[0], objects[2]]);
    expect(sheetConflicts(['Shifts', 'Notes'], objects, 'Contact')).toEqual([objects[2]]);
    expect(sheetConflicts(['Shifts', 'Notes'], objects)).toEqual([]);
    expect(sheetConflicts(['Shifts'], objects, 'Contact')).toEqual([]);
    expect(sheetConflicts(['People', 'More'], undefined, 'Contact')).toEqual([]);
  });
});

describe('the sheets of an upload of several objects (R-IT20)', () => {
  const programs = {
    name: 'Programs',
    headers: ['Name', 'Code'],
    records: [{ Name: 'Reading', Code: 'P-1' }]
  };
  const sessions = {
    name: 'Sessions',
    headers: ['Name', 'Program Code', 'Notes'],
    records: [
      { Name: 'Intro', 'Program Code': 'P-1', Notes: '' },
      { Name: 'Advanced', 'Program Code': 'P-1', Notes: 'x' }
    ]
  };

  it('keeps the same heading of two objects as two columns, the later named with its sheet', () => {
    const combined = combineObjectSheets(
      [programs, sessions],
      [
        { Name: 'Program__c.Name', Code: 'Program__c.Code__c' },
        { Name: 'Session__c.Name', 'Program Code': 'Session__c.Program__c', Notes: IGNORE }
      ],
      ['Program__c', 'Session__c'],
      IGNORE,
      BLANK
    );
    expect(combined.headers).toEqual(['Name', 'Code', 'Name (Sessions)', 'Program Code', 'Notes']);
    expect(combined.targets).toEqual({
      Name: 'Program__c.Name',
      Code: 'Program__c.Code__c',
      'Name (Sessions)': 'Session__c.Name',
      'Program Code': 'Session__c.Program__c',
      Notes: IGNORE
    });
    expect(combined.records).toEqual([
      { Name: 'Reading', Code: 'P-1', 'Name (Sessions)': '', 'Program Code': '', Notes: '' },
      { Name: '', Code: '', 'Name (Sessions)': 'Intro', 'Program Code': 'P-1', Notes: '' },
      { Name: '', Code: '', 'Name (Sessions)': 'Advanced', 'Program Code': 'P-1', Notes: 'x' }
    ]);
    expect(combined.examples['Name (Sessions)']).toEqual(['Intro', 'Advanced']);
    expect(combined.examples.Notes).toEqual([BLANK, 'x']);
  });

  it('joins headings of one object, or mapped to one field, as one column', () => {
    const others = {
      name: 'More',
      headers: ['Name', 'Title'],
      records: [{ Name: 'Art', Title: 'A' }]
    };
    const combined = combineObjectSheets(
      [programs, others],
      [{ Name: 'Program__c.Name' }, { Name: 'Program__c.Name', Title: 'Program__c.Name' }],
      ['Program__c', 'Program__c'],
      IGNORE
    );
    expect(combined.headers).toEqual(['Name', 'Code']);
    expect(combined.records[1]).toEqual({ Name: 'Art', Code: '' });
  });

  it('orders the sheets parents first, keeping the file order within an object', () => {
    const moreSessions = { name: 'More sessions', headers: [], records: [] };
    const loose = { name: 'Notes', headers: [], records: [] };
    const objectOf = {
      Sessions: 'Session__c',
      Programs: 'Program__c',
      'More sessions': 'Session__c',
      Notes: 'Venue__c'
    };
    expect(
      sheetsInLoadOrder([loose, sessions, programs, moreSessions], objectOf, [
        'Program__c',
        'Session__c'
      ]).map((sheet) => sheet.name)
    ).toEqual(['Programs', 'Sessions', 'More sessions', 'Notes']);
  });
});
