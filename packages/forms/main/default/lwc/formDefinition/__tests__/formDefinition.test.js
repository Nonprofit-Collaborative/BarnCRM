import {
  SCHEMA_VERSION,
  allFields,
  checkDefinition,
  conditionFields,
  emptyDefinition,
  isPublic,
  objectOf,
  parseDefinition,
  serializeDefinition,
  targetsOf,
  withDefaults
} from 'c/formDefinition';

const codes = (problems) => problems.map((found) => found.code);

function good() {
  return {
    schemaVersion: 1,
    steps: [
      {
        key: 'you',
        title: 'You',
        fields: [
          {
            key: 'last',
            label: 'Last Name',
            type: 'text',
            target: { record: 'person', field: 'LastName' }
          },
          {
            key: 'email',
            label: 'Email',
            type: 'email',
            target: { record: 'person', field: 'Email' }
          },
          {
            key: 'org',
            label: 'Organization',
            type: 'text',
            target: { record: 'employer', field: 'Name' },
            showWhen: { all: [{ field: 'email', op: 'isNotBlank' }] }
          }
        ]
      },
      {
        key: 'help',
        title: 'Help',
        showWhen: { any: [{ field: 'org', op: 'equals', value: 'Acme' }] },
        fields: [
          {
            key: 'kind',
            label: 'Kind',
            type: 'picklist',
            options: [{ label: 'Food', value: 'food' }],
            target: { record: 'interest', field: 'Kind__c' }
          }
        ]
      }
    ],
    records: [
      { key: 'person', kind: 'person' },
      { key: 'employer', kind: 'organization' },
      {
        key: 'interest',
        kind: 'related',
        object: 'Interest__c',
        links: { Contact__c: 'person', Event__c: 'context' },
        values: { Source__c: 'Form' }
      }
    ]
  };
}

describe('c/formDefinition', () => {
  it('accepts a good definition and fills the matching defaults', () => {
    const { definition, problems } = parseDefinition(JSON.stringify(good()));
    expect(problems).toEqual([]);
    expect(definition.records[0].matching).toEqual({
      rule: 'emailThenNamePostal',
      onMatch: 'fillBlanks'
    });
    expect(definition.records[1].matching.rule).toBe('name');
    expect(definition.records[2].matching).toBeUndefined();
    expect(definition.steps[0].fields[0].required).toBe(false);
  });

  it('opens a blank form as the empty definition and refuses text that is not one', () => {
    expect(parseDefinition('').definition).toEqual(emptyDefinition());
    expect(parseDefinition('{oops').problems).toEqual([{ code: 'notJson', args: [] }]);
    expect(parseDefinition('[1]').definition).toBeNull();
    expect(emptyDefinition().schemaVersion).toBe(SCHEMA_VERSION);
    expect(codes(checkDefinition(null))).toEqual(['notJson']);
  });

  it('round trips through its stored text', () => {
    const text = serializeDefinition(withDefaults(good()));
    expect(parseDefinition(text).definition).toEqual(withDefaults(good()));
  });

  it('names each broken field', () => {
    const definition = good();
    definition.steps[0].fields.push(
      { key: 'email', label: 'Again', type: 'email' },
      { key: '9bad', label: '', type: 'colour' },
      { key: 'pick', label: 'Pick', type: 'picklist', options: [] },
      { key: 'where', label: 'Where', type: 'text', target: { record: 'nobody', field: 'X' } },
      { key: 'blankTarget', label: 'B', type: 'text', target: { record: 'person', field: '' } }
    );
    expect(checkDefinition(definition)).toEqual([
      { code: 'duplicateKey', args: ['email'] },
      { code: 'badKey', args: ['9bad'] },
      { code: 'noLabel', args: ['9bad'] },
      { code: 'badType', args: ['9bad', 'colour'] },
      { code: 'noOptions', args: ['pick'] },
      { code: 'unknownRecord', args: ['where', 'nobody'] },
      { code: 'noTargetField', args: ['blankTarget'] }
    ]);
  });

  it('refuses a condition on a later or unknown question, or one with no value', () => {
    const definition = good();
    definition.steps[0].fields[0].showWhen = { all: [{ field: 'email', op: 'isBlank' }] };
    definition.steps[0].showWhen = { all: [{ field: 'last', op: 'isBlank' }] };
    definition.steps[1].fields[0].showWhen = { any: [{ field: 'org', op: 'equals' }] };
    definition.steps[0].fields[1].showWhen = { all: [] };
    definition.steps[0].fields[2].showWhen = {
      all: [{ all: [{ all: [{ all: [{ field: 'email', op: 'isBlank' }] }] }] }]
    };
    expect(checkDefinition(definition)).toEqual([
      { code: 'conditionNotEarlier', args: ['You', 'last'] },
      { code: 'conditionNotEarlier', args: ['last', 'email'] },
      { code: 'badCondition', args: ['email'] },
      { code: 'conditionTooDeep', args: ['org'] },
      { code: 'conditionNeedsValue', args: ['kind', 'org'] }
    ]);
  });

  it('checks the records and what they need mapped', () => {
    const definition = good();
    definition.records.push(
      { key: 'second', kind: 'person', matching: { rule: 'phone', onMatch: 'fillBlanks' } },
      { key: 'thing', kind: 'related', object: 'Account', links: { Owner__c: 'nowhere' } },
      { key: 'person', kind: 'gadget' }
    );
    definition.steps[0].fields[0].target = null;
    expect(codes(checkDefinition(definition))).toEqual([
      'twoPeople',
      'badMatching',
      'relatedNeedsObject',
      'duplicateRecord',
      'badRecord',
      'badLink',
      'personNeedsLastName',
      'personNeedsLastName'
    ]);
  });

  it('counts steps, fields and records against their limits', () => {
    const definition = good();
    definition.steps = [];
    expect(codes(checkDefinition(definition))).toContain('noSteps');
    definition.steps = Array.from({ length: 21 }, (_, i) => ({
      key: `s${i}`,
      fields: [{ key: `f${i}`, label: 'F', type: 'text' }]
    }));
    definition.steps[0].fields = Array.from({ length: 101 }, (_, i) => ({
      key: `g${i}`,
      label: 'G',
      type: 'text'
    }));
    definition.steps[1].fields = [];
    definition.records = Array.from({ length: 11 }, (_, i) => ({
      key: `r${i}`,
      kind: 'related',
      object: 'Thing__c'
    }));
    definition.schemaVersion = 2;
    expect(codes(checkDefinition(definition))).toEqual(
      expect.arrayContaining([
        'schemaVersion',
        'tooManySteps',
        'tooManyRecords',
        'emptyStep',
        'tooManyFields'
      ])
    );
  });

  it('lists fields, targets, condition fields and objects', () => {
    const definition = withDefaults(good());
    expect(allFields(definition).map((field) => `${field.stepIndex}:${field.key}`)).toEqual([
      '0:last',
      '0:email',
      '0:org',
      '1:kind'
    ]);
    expect(targetsOf(definition, 'person')).toEqual({ lastname: 'last', email: 'email' });
    expect(conditionFields(definition.steps[1].showWhen)).toEqual(['org']);
    expect(conditionFields(null)).toEqual([]);
    expect(definition.records.map(objectOf)).toEqual(['Contact', 'Account', 'Interest__c']);
    expect(objectOf(null)).toBeNull();
  });

  it('checks the public settings and refuses overwriting on a public form (C-42b)', () => {
    const open = { ...good(), public: { enabled: true, minSeconds: 5, hourlyLimit: 20 } };
    expect(isPublic(open)).toBe(true);
    expect(checkDefinition(open)).toEqual([]);
    expect(isPublic(good())).toBe(false);

    const wrong = {
      ...good(),
      public: { enabled: true, minSeconds: -1, hourlyLimit: 2.5, confirmation: 'x'.repeat(1001) }
    };
    expect(codes(checkDefinition(wrong))).toEqual([
      'badPublicSeconds',
      'badPublicLimit',
      'badPublicConfirmation'
    ]);
    expect(codes(checkDefinition({ ...good(), public: [] }))).toEqual(['badPublic']);

    const overwriting = { ...good(), public: { enabled: true } };
    overwriting.records[0].matching = { rule: 'email', onMatch: 'overwrite' };
    expect(codes(checkDefinition(overwriting))).toEqual(['publicOverwrite']);
    expect(codes(checkDefinition({ ...overwriting, public: { enabled: false } }))).toEqual([]);
  });
});
