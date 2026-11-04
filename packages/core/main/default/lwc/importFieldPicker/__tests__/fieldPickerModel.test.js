import { buildModel, matches, selectedText, splitOption, stepIndex } from '../fieldPickerModel';

const PEOPLE = [
  { label: 'Do not load', value: 'Ignore' },
  { label: 'Person: First Name', value: 'Contact1.FirstName' },
  { label: 'Person: Last Name', value: 'Contact1.LastName' },
  { label: 'Second person: Email', value: 'Contact2.Email' },
  { label: 'Organization: Name', value: 'Organization.Name' },
  { label: 'Create New Field', value: 'NewField' }
];

describe('field picker model', () => {
  it('takes the group from a dotted field with a labeled prefix', () => {
    expect(splitOption(PEOPLE[1])).toEqual({ group: 'Person', name: 'First Name' });
    expect(splitOption({ label: 'Account Name: old', value: 'Name' })).toEqual({
      group: '',
      name: 'Account Name: old'
    });
  });

  it('matches every typed word in any order, ignoring case', () => {
    expect(matches('Second person: Email', 'email second')).toBe(true);
    expect(matches('Second person: Email', 'phone')).toBe(false);
    expect(matches('anything', '')).toBe(true);
  });

  it('pins Do not load first and groups the rest in the order given', () => {
    const model = buildModel({ options: PEOPLE, query: '', pinnedValue: 'Ignore' });
    expect(model.pinned.value).toBe('Ignore');
    expect(model.groups.map((group) => group.label)).toEqual([
      'Person',
      'Second person',
      'Organization',
      ''
    ]);
    expect(model.items[0].value).toBe('Ignore');
    expect(model.count).toBe(5);
  });

  it('filters by what is typed but keeps Do not load', () => {
    const model = buildModel({ options: PEOPLE, query: 'email', pinnedValue: 'Ignore' });
    expect(model.items.map((item) => item.value)).toEqual(['Ignore', 'Contact2.Email']);
    expect(model.count).toBe(1);
    const none = buildModel({ options: PEOPLE, query: 'zzz', pinnedValue: 'Ignore' });
    expect(none.count).toBe(0);
    expect(none.pinned).not.toBeNull();
  });

  it('marks fields other columns use, and the chosen one', () => {
    const model = buildModel({
      options: PEOPLE,
      query: '',
      usedValues: ['contact1.firstname', 'Ignore'],
      selected: 'Contact1.LastName',
      pinnedValue: 'Ignore'
    });
    const byValue = Object.fromEntries(model.items.map((item) => [item.value, item]));
    expect(byValue['Contact1.FirstName'].used).toBe(true);
    expect(byValue.Ignore.used).toBe(false);
    expect(byValue['Contact1.LastName'].selected).toBe(true);
  });

  it('reads the chosen label and steps along the list', () => {
    expect(selectedText(PEOPLE, 'Contact2.Email')).toBe('Second person: Email');
    expect(selectedText(PEOPLE, 'missing')).toBe('');
    expect(stepIndex(-1, 1, 3)).toBe(0);
    expect(stepIndex(-1, -1, 3)).toBe(2);
    expect(stepIndex(2, 1, 3)).toBe(2);
    expect(stepIndex(1, -1, 3)).toBe(0);
    expect(stepIndex(0, 1, 0)).toBe(-1);
  });
});
