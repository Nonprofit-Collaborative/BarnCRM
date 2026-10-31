import {
  MAILCHIMP,
  CONSTANT_CONTACT,
  ALL_COLUMNS,
  TAG_PATH,
  isEmailLayout,
  columnsFor,
  emailKey,
  createCollector
} from 'c/donorSegmentExport';

describe('donorSegmentExport', () => {
  it('knows which layouts are for email tools', () => {
    expect(isEmailLayout(MAILCHIMP)).toBe(true);
    expect(isEmailLayout(CONSTANT_CONTACT)).toBe(true);
    expect(isEmailLayout(ALL_COLUMNS)).toBe(false);
    expect(isEmailLayout('toString')).toBe(false);
  });

  it('lays out Mailchimp with its own field names and the tag last', () => {
    const columns = columnsFor(MAILCHIMP, [{ label: 'Ignored', path: 'Name' }]);
    expect(columns.map((column) => column.label)).toEqual([
      'Email Address',
      'First Name',
      'Last Name',
      'Tags'
    ]);
    expect(columns[3].path).toBe(TAG_PATH);
  });

  it('lays out Constant Contact with the mailing address', () => {
    const columns = columnsFor(CONSTANT_CONTACT, []);
    expect(columns.map((column) => column.path)).toEqual([
      'Email',
      'FirstName',
      'LastName',
      'MailingStreet',
      'MailingCity',
      'MailingState',
      'MailingPostalCode',
      'MailingCountry'
    ]);
    expect(columns[3].label).toBe('Street address line 1');
  });

  it('keeps the segment columns for All Columns', () => {
    const segment = [
      { label: 'Full Name', path: 'Name' },
      { label: 'Donor Level', path: 'Donor_Level__r.Name' }
    ];
    expect(columnsFor(ALL_COLUMNS, segment)).toEqual(segment);
    expect(columnsFor(ALL_COLUMNS, undefined)).toEqual([]);
  });

  it('compares addresses without case or surrounding spaces', () => {
    expect(emailKey('  Ana@Example.ORG ')).toBe('ana@example.org');
    expect(emailKey(null)).toBe('');
    expect(emailKey(undefined)).toBe('');
  });

  it('writes each address once across pages, tags the rows and flattens the street', () => {
    const collector = createCollector(MAILCHIMP, 'Lapsed Donors');
    const first = collector.add([
      { Id: '1', Email: ' ana@example.org ', FirstName: 'Ana', MailingStreet: '1 Main St\nApt 2' },
      { Id: '2', Email: 'ANA@example.org', FirstName: 'Luis' },
      { Id: '3', Email: '', FirstName: 'Nobody' }
    ]);
    const second = collector.add([
      { Id: '4', Email: 'ana@example.org' },
      { Id: '5', Email: 'bo@example.org' }
    ]);
    expect(first).toHaveLength(1);
    expect(first[0].Email).toBe('ana@example.org');
    expect(first[0].MailingStreet).toBe('1 Main St, Apt 2');
    expect(first[0][TAG_PATH]).toBe('Lapsed Donors');
    expect(second.map((row) => row.Id)).toEqual(['5']);
    expect(collector.duplicates).toBe(2);
  });

  it('passes All Columns rows through untouched', () => {
    const collector = createCollector(ALL_COLUMNS, 'Anything');
    const rows = [{ Id: '1', Name: 'Acme' }, { Id: '2' }];
    expect(collector.add(rows)).toBe(rows);
    expect(collector.add(undefined)).toEqual([]);
    expect(collector.duplicates).toBe(0);
  });
});
