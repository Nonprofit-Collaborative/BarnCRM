import {
  defaultSheets,
  distinctHeaders,
  combineSheets,
  exampleText,
  sheetConflicts,
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
