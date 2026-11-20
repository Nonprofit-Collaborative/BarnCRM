import {
  READ,
  EDIT,
  NONE,
  withItems,
  withoutItem,
  conflicts,
  buildChange,
  accessWord,
  askedWord,
  previewRows,
  filterFields
} from 'c/fieldAccessPlan';

const WORDS = {
  read: 'Read',
  edit: 'Read and Edit',
  none: 'No Access',
  wholeRecord: '(The kind of record)',
  reasons: { asked: 'Asked', neededForFields: 'Needed for field access' }
};
const CONTACT = { name: 'Contact', label: 'Contact' };
const EMAIL = { name: 'Email', label: 'Email', readOnly: false };
const FORMULA = { name: 'Age__c', label: 'Age', readOnly: true };

describe('fieldAccessPlan', () => {
  it('adds fields, and gives a read-only field Read when Edit is asked', () => {
    const items = withItems([], CONTACT, [EMAIL, FORMULA], EDIT);
    expect(items.map((item) => [item.key, item.access])).toEqual([
      ['Contact.Email', EDIT],
      ['Contact.Age__c', READ]
    ]);
  });

  it('replaces an item asked again and keeps the others', () => {
    let items = withItems([], CONTACT, [EMAIL], EDIT);
    items = withItems(items, CONTACT, [], READ);
    items = withItems(items, CONTACT, [EMAIL], NONE);
    expect(items.map((item) => [item.key, item.access])).toEqual([
      ['Contact.', READ],
      ['Contact.Email', NONE]
    ]);
    expect(withoutItem(items, 'Contact.').map((item) => item.key)).toEqual(['Contact.Email']);
  });

  it('names a kind of record set to No Access while its fields are given access', () => {
    let items = withItems([], CONTACT, [], NONE);
    expect(conflicts(items)).toEqual([]);
    items = withItems(items, CONTACT, [EMAIL], READ);
    expect(conflicts(items)).toEqual(['Contact']);
  });

  it('builds the change document with object-qualified field names', () => {
    const items = withItems(withItems([], CONTACT, [], READ), CONTACT, [EMAIL], EDIT);
    expect(buildChange(['0PS1'], items)).toEqual({
      version: 1,
      setIds: ['0PS1'],
      items: [
        { object: 'Contact', field: null, access: READ },
        { object: 'Contact', field: 'Contact.Email', access: EDIT }
      ]
    });
  });

  it('words access levels', () => {
    expect(accessWord(true, true, WORDS)).toBe('Read and Edit');
    expect(accessWord(true, false, WORDS)).toBe('Read');
    expect(accessWord(false, false, WORDS)).toBe('No Access');
    expect(askedWord(EDIT, WORDS)).toBe('Read and Edit');
    expect(askedWord(NONE, WORDS)).toBe('No Access');
  });

  it('words preview rows', () => {
    const [objectRow, fieldRow] = previewRows(
      [
        {
          setId: 's',
          objectName: 'Contact',
          fieldName: null,
          nowRead: false,
          afterRead: true,
          reason: 'neededForFields'
        },
        {
          setId: 's',
          objectName: 'Contact',
          fieldName: 'Email',
          fieldLabel: 'Email',
          nowRead: true,
          afterRead: true,
          afterEdit: true,
          reason: 'other'
        }
      ],
      WORDS
    );
    expect(objectRow.fieldText).toBe('(The kind of record)');
    expect(objectRow.nowText).toBe('No Access');
    expect(objectRow.afterText).toBe('Read');
    expect(objectRow.whyText).toBe('Needed for field access');
    expect(fieldRow.fieldText).toBe('Email');
    expect(fieldRow.afterText).toBe('Read and Edit');
    expect(fieldRow.whyText).toBe('other');
    expect(objectRow.key).not.toBe(fieldRow.key);
  });

  it('filters fields by label or API name', () => {
    expect(filterFields([EMAIL, FORMULA], 'age').map((field) => field.name)).toEqual(['Age__c']);
    expect(filterFields([EMAIL, FORMULA], ' ')).toHaveLength(2);
    expect(filterFields([EMAIL, FORMULA], 'EMAIL')).toHaveLength(1);
  });
});
