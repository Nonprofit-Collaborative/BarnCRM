import { needsContext, planWrites, questionsByRecord } from 'c/formMapping';

const definition = {
  schemaVersion: 1,
  steps: [
    {
      key: 'one',
      fields: [
        { key: 'org', label: 'Org', type: 'text', target: { record: 'employer', field: 'Name' } },
        {
          key: 'last',
          label: 'Last',
          type: 'text',
          target: { record: 'person', field: 'LastName' }
        },
        {
          key: 'email',
          label: 'Email',
          type: 'email',
          target: { record: 'person', field: 'Email' }
        },
        { key: 'note', label: 'Note', type: 'textarea' },
        {
          key: 'kind',
          label: 'Kind',
          type: 'text',
          target: { record: 'interest', field: 'Kind__c' }
        }
      ]
    }
  ],
  records: [
    {
      key: 'interest',
      kind: 'related',
      object: 'Interest__c',
      links: { Contact__c: 'person', Event__c: 'context' },
      values: { Source__c: 'Form' }
    },
    { key: 'employer', kind: 'organization', matching: { rule: 'name', onMatch: 'overwrite' } },
    { key: 'person', kind: 'person', matching: { rule: 'email', onMatch: 'fillBlanks' } }
  ]
};

describe('c/formMapping', () => {
  it('plans the person, then the organization, then related records, with their values', () => {
    const plan = planWrites(definition, { last: 'Lee', email: 'pat@example.org', kind: 'Food' });
    expect(plan.map((record) => record.key)).toEqual(['person', 'employer', 'interest']);
    expect(plan[0]).toEqual({
      key: 'person',
      kind: 'person',
      object: 'Contact',
      fields: { LastName: 'Lee', Email: 'pat@example.org' },
      links: {},
      matching: { rule: 'email', onMatch: 'fillBlanks' }
    });
    expect(plan[1].fields).toEqual({});
    expect(plan[1].object).toBe('Account');
    expect(plan[2]).toMatchObject({
      object: 'Interest__c',
      fields: { Source__c: 'Form', Kind__c: 'Food' },
      links: { Contact__c: 'person', Event__c: 'context' },
      matching: null
    });
  });

  it('lets an answer of false through and nothing for an unanswered question', () => {
    const plan = planWrites(
      {
        steps: [
          {
            key: 's',
            fields: [{ key: 'ok', type: 'checkbox', target: { record: 'r', field: 'Ok__c' } }]
          }
        ],
        records: [{ key: 'r', kind: 'related', object: 'Thing__c' }]
      },
      { ok: false }
    );
    expect(plan[0].fields).toEqual({ Ok__c: false });
    expect(planWrites(definition, undefined)[0].fields).toEqual({});
    expect(planWrites(null, {})).toEqual([]);
  });

  it('groups questions by record and says when a form needs the record it is filled from', () => {
    const grouped = questionsByRecord(definition);
    expect(grouped.person.map((field) => field.key)).toEqual(['last', 'email']);
    expect(grouped.note).toBeUndefined();
    expect(needsContext(definition)).toBe(true);
    expect(needsContext({ records: [{ key: 'p', kind: 'person' }] })).toBe(false);
    expect(needsContext(null)).toBe(false);
  });
});
