import {
  OBJECT_FLAGS,
  FIELD_FLAGS,
  diffRows,
  similarity,
  visibleRows,
  countDifferences
} from 'c/accessDiff';

const WORDS = {
  flags: {
    read: 'Read',
    create: 'Create',
    edit: 'Edit',
    del: 'Delete',
    viewAll: 'View All',
    modifyAll: 'Modify All'
  },
  onlyIn: 'Only {0}: {1}.',
  nameA: 'Pat',
  nameB: 'Sam',
  none: 'None'
};

const row = (name, label, flags, extra = {}) => ({
  name,
  label,
  ...Object.fromEntries(flags.map((flag) => [flag, true])),
  ...extra
});

describe('diffRows', () => {
  it('names what each side has alone and keeps rows that match', () => {
    const a = [row('Gift__c', 'Gift', ['read', 'edit']), row('Fund__c', 'Fund', ['read'])];
    const b = [row('Gift__c', 'Gift', ['read', 'viewAll']), row('Fund__c', 'Fund', ['read'])];
    const rows = diffRows(a, b, OBJECT_FLAGS, WORDS);

    expect(rows.map((r) => r.name)).toEqual(['Fund__c', 'Gift__c']);
    expect(rows[0]).toMatchObject({ differs: false, difference: '', aText: 'Read', bText: 'Read' });
    expect(rows[1]).toMatchObject({
      differs: true,
      aText: 'Read, Edit',
      bText: 'Read, View All',
      difference: 'Only Pat: Edit. Only Sam: View All.'
    });
  });

  it('treats a name found on one side only as no access on the other', () => {
    const rows = diffRows(
      [row('Gift__c', 'Gift', ['read', 'create'])],
      [row('Fund__c', 'Fund', ['read'])],
      OBJECT_FLAGS,
      WORDS
    );

    expect(rows[0]).toMatchObject({
      name: 'Fund__c',
      aText: 'None',
      difference: 'Only Sam: Read.'
    });
    expect(rows[1]).toMatchObject({
      name: 'Gift__c',
      bText: 'None',
      difference: 'Only Pat: Read, Create.'
    });
  });

  it('counts a field nobody can be kept from as always readable', () => {
    const rows = diffRows(
      [row('Name', 'Name', [], { always: true })],
      [row('Name', 'Name', ['read'])],
      FIELD_FLAGS,
      WORDS
    );

    expect(rows[0]).toMatchObject({ differs: false, aText: 'Read', bText: 'Read' });
  });

  it('compares only the flags it is given', () => {
    const rows = diffRows(
      [row('Description', 'Description', ['read', 'edit', 'create'])],
      [row('Description', 'Description', ['read'])],
      FIELD_FLAGS,
      WORDS
    );

    expect(rows[0].difference).toBe('Only Pat: Edit.');
  });

  it('sorts by label then name and handles empty sides', () => {
    expect(diffRows([], [], OBJECT_FLAGS, WORDS)).toEqual([]);
    const rows = diffRows(
      [row('B__c', 'Same', ['read']), row('A__c', 'Same', ['read']), row('C__c', 'Alpha', [])],
      [],
      OBJECT_FLAGS,
      WORDS
    );
    expect(rows.map((r) => r.name)).toEqual(['C__c', 'A__c', 'B__c']);
    expect(rows[0]).toMatchObject({ differs: false, aText: 'None' });
  });

  it('leaves an unknown placeholder alone', () => {
    const rows = diffRows([row('A__c', 'A', ['read'])], [], OBJECT_FLAGS, {
      ...WORDS,
      onlyIn: '{0} {2}'
    });
    expect(rows[0].difference).toBe('Pat {2}');
  });
});

describe('similarity', () => {
  it('is shared permissions over all permissions given', () => {
    const a = [row('Gift__c', 'Gift', ['read', 'edit']), row('Fund__c', 'Fund', ['read'])];
    const b = [row('Gift__c', 'Gift', ['read']), row('Fund__c', 'Fund', ['read'])];
    // Shared: Gift read, Fund read. Either: those two and Gift edit.
    expect(similarity(a, b, OBJECT_FLAGS)).toBe(67);
  });

  it('is 100 for identical sides and for two sides that give nothing', () => {
    const a = [row('Gift__c', 'Gift', ['read'])];
    expect(similarity(a, a, OBJECT_FLAGS)).toBe(100);
    expect(similarity([], [], OBJECT_FLAGS)).toBe(100);
  });

  it('is 0 when nothing is shared', () => {
    expect(
      similarity([row('A__c', 'A', ['read'])], [row('B__c', 'B', ['read'])], OBJECT_FLAGS)
    ).toBe(0);
  });
});

describe('visibleRows and countDifferences', () => {
  const rows = [{ differs: true }, { differs: false }, { differs: true }];

  it('filters to differences or keeps everything', () => {
    expect(visibleRows(rows, true)).toHaveLength(2);
    expect(visibleRows(rows, false)).toHaveLength(3);
    expect(countDifferences(rows)).toBe(2);
  });
});
