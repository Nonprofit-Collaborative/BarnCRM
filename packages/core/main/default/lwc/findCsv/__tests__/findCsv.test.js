import { BYTE_ORDER_MARK, cell, fileName, toCsv, valueAt } from 'c/findCsv';

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
    expect(fileName('Gift__c', new Date('2026-10-12T10:00:00Z'))).toBe('Gift__c-2026-10-12.csv');
  });
});
