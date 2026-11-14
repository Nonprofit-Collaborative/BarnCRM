import { barnName, nameOptions, shownColumns, withDetails, withFlags } from 'c/accessExplorerRows';

const WORDS = {
  yes: 'Yes',
  always: 'Always',
  kinds: { profile: 'Profile', permissionSet: 'Permission set' },
  barnNames: { role: '{0} (BarnCRM role)', extraPermission: '{0} (extra permission)' }
};

describe('c/accessExplorerRows', () => {
  it('writes each permission as the yes word or blank, and keys the row', () => {
    const row = withFlags(
      { id: 'r1', label: 'Gift Officer', kind: 'profile', read: true, edit: false, del: true },
      WORDS
    );
    expect(row).toMatchObject({
      key: 'r1',
      label: 'Gift Officer',
      kindLabel: 'Profile',
      readText: 'Yes',
      createText: '',
      editText: '',
      delText: 'Yes',
      viewAllText: '',
      modifyAllText: ''
    });
  });

  it('reads Always for a field nobody can be kept from, and names a BarnCRM role', () => {
    const row = withFlags(
      { name: 'Team_Member', label: 'Team Member', barnKind: 'role', always: true, kind: 'x' },
      WORDS
    );
    expect(row.key).toBe('Team_Member');
    expect(row.readText).toBe('Always');
    expect(row.label).toBe('Team Member (BarnCRM role)');
    expect(row.kindLabel).toBe('');
  });

  it('adds details in brackets only when there are any', () => {
    expect(withDetails('Pat', ['', 'Standard User', null])).toBe('Pat (Standard User)');
    expect(withDetails('Pat', ['', null])).toBe('Pat');
  });

  it('leaves a name with no BarnCRM kind or no patterns as it is', () => {
    expect(barnName('Admin', '', WORDS.barnNames)).toBe('Admin');
    expect(barnName('Admin', 'role', undefined)).toBe('Admin');
  });

  it('hides technical columns unless asked, and drops the mark either way', () => {
    const columns = [
      { label: 'Field', fieldName: 'label' },
      { label: 'API Name', fieldName: 'name', technical: true }
    ];
    expect(shownColumns(columns, false)).toEqual([{ label: 'Field', fieldName: 'label' }]);
    expect(shownColumns(columns, true)).toEqual([
      { label: 'Field', fieldName: 'label' },
      { label: 'API Name', fieldName: 'name' }
    ]);
  });

  it('adds the API name to an option when technical names show or two labels match', () => {
    const options = [
      { label: 'Gift', value: 'Gift__c' },
      { label: 'Note', value: 'Note__c' },
      { label: 'Note', value: 'Old_Note__c' }
    ];
    expect(nameOptions(options, false).map((option) => option.label)).toEqual([
      'Gift',
      'Note (Note__c)',
      'Note (Old_Note__c)'
    ]);
    expect(nameOptions(options, true)[0].label).toBe('Gift (Gift__c)');
    expect(nameOptions([{ label: 'All', value: '' }], true)[0].label).toBe('All');
  });
});
