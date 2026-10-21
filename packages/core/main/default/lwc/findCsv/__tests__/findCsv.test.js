import {
  BYTE_ORDER_MARK,
  cell,
  fileName,
  format,
  messageFrom,
  toCsv,
  valueAt,
  zonedDateTime
} from 'c/findCsv';

describe('c/findCsv', () => {
  it('reads a value through a parent path', () => {
    const row = { Name: 'Gift 1', Donor_Contact__r: { Account: { Name: 'Garcia household' } } };
    expect(valueAt(row, 'Donor_Contact__r.Account.Name')).toBe('Garcia household');
    expect(valueAt(row, 'Missing__r.Name')).toBeUndefined();
  });

  it('quotes only what needs quoting', () => {
    expect(cell('plain')).toBe('plain');
    expect(cell('Smith, Jane')).toBe('"Smith, Jane"');
    expect(cell('She said "hi"')).toBe('"She said ""hi"""');
    expect(cell('two\nlines')).toBe('"two\nlines"');
    expect(cell(null)).toBe('');
    expect(cell(0)).toBe('0');
    expect(cell(false)).toBe('false');
  });

  it('defuses values a spreadsheet would run as formulas', () => {
    expect(cell('=SUM(A1:A9)')).toBe("'=SUM(A1:A9)");
    expect(cell('+1 555')).toBe("'+1 555");
    expect(cell('-2+3')).toBe("'-2+3");
    expect(cell('@cmd')).toBe("'@cmd");
    expect(cell('\tTabbed')).toBe("'\tTabbed");
    expect(cell('\rReturn')).toBe('"\'\rReturn"');
    expect(cell('=HYPERLINK("x","y")')).toBe('"\'=HYPERLINK(""x"",""y"")"');
    expect(cell('a=b')).toBe('a=b');
    expect(cell(-5)).toBe('-5');
  });

  it('leaves text that is only a negative number alone', () => {
    expect(cell('-25.00')).toBe('-25.00');
    expect(cell('-7')).toBe('-7');
    expect(cell('-7e3')).toBe("'-7e3");
    expect(cell('-1-1')).toBe("'-1-1");
  });

  it('writes a byte-order mark, a header of labels and one line per row', () => {
    const csv = toCsv(
      [
        { label: 'Name', path: 'Name' },
        { label: 'Donor > Last Name', path: 'Donor_Contact__r.LastName' }
      ],
      [{ Name: 'Gift 1', Donor_Contact__r: { LastName: 'Muñoz' } }, { Name: 'Gift 2' }]
    );
    expect(csv.startsWith(BYTE_ORDER_MARK)).toBe(true);
    expect(csv.slice(1)).toBe('Name,Donor > Last Name\r\nGift 1,Muñoz\r\nGift 2,\r\n');
  });

  it('names the file after the object and the day', () => {
    expect(fileName('Gift__c', new Date(2026, 9, 12, 10, 0))).toBe('Gift__c-2026-10-12.csv');
    expect(fileName('Gift__c', new Date(2026, 9, 12, 10, 0), 'xlsx')).toBe(
      'Gift__c-2026-10-12.xlsx'
    );
  });

  it('dates the file by the local day, even late in the evening (UI-14)', () => {
    // 11:30 pm local: in a US time zone the UTC date is already the next day.
    expect(fileName('Gift__c', new Date(2026, 9, 12, 23, 30))).toBe('Gift__c-2026-10-12.csv');
    expect(fileName('Gift__c', new Date(2026, 0, 1, 0, 5))).toBe('Gift__c-2026-01-01.csv');
  });

  it('writes a date-time as the clock reads in the person time zone', () => {
    const noonUtc = '2026-01-05T12:00:00.000Z';
    expect(zonedDateTime(noonUtc, 'UTC')).toBe('2026-01-05 12:00:00');
    expect(zonedDateTime(noonUtc, 'America/Los_Angeles')).toBe('2026-01-05 04:00:00');
    expect(zonedDateTime('2026-01-05T03:00:00.000Z', 'America/New_York')).toBe(
      '2026-01-04 22:00:00'
    );
    expect(zonedDateTime('2026-07-01T00:00:00.000Z', 'Europe/London')).toBe('2026-07-01 01:00:00');
    expect(zonedDateTime('soon', 'UTC')).toBe('soon');
    expect(zonedDateTime(null, 'UTC')).toBeNull();
  });

  it('fills a label and reads a failed call', () => {
    expect(format('{0} of {1}', 'one', 'two')).toBe('one of two');
    expect(messageFrom({ body: { message: 'From the server' } })).toBe('From the server');
    expect(messageFrom(new Error('Thrown'))).toBe('Thrown');
    expect(messageFrom('plain')).toBe('c.Core_UnexpectedError');
  });
});
