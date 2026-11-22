import { answerRows, submissionView, writtenRecords } from 'c/formSubmissionModel';

const DEFINITION = JSON.stringify({
  schemaVersion: 1,
  steps: [
    {
      key: 'you',
      fields: [
        { key: 'first', label: 'First', type: 'text' },
        { key: 'last', label: 'Last', type: 'text' },
        {
          key: 'role',
          label: 'Role',
          type: 'picklist',
          options: [
            { value: 'vol', label: 'Volunteer' },
            { value: 'board', label: 'Board' }
          ]
        }
      ]
    },
    { key: 'more', fields: [{ key: 'agree', label: 'Agree', type: 'checkbox' }, 'not a field'] }
  ]
});

describe('c/formSubmissionModel', () => {
  it('lists the answers in the order the version asks, an option by its label', () => {
    const rows = answerRows(
      JSON.stringify({ role: 'vol', last: 'Lee', agree: false, first: 'Pat', retired: 'x' }),
      DEFINITION
    );
    expect(rows.map((row) => row.label)).toEqual(['First', 'Last', 'Role', 'Agree', 'retired']);
    expect(rows[2]).toEqual({ key: 'role', label: 'Role', type: 'picklist', value: 'Volunteer' });
    expect(rows[3].value).toBe('false');
    expect(rows[4]).toEqual({ key: 'retired', label: 'retired', type: 'text', value: 'x' });
  });

  it('keeps every answer under its key when the version cannot be read', () => {
    const rows = answerRows(JSON.stringify({ last: 'Lee', tags: ['a'], none: null }), 'not json');
    expect(rows).toEqual([
      { key: 'last', label: 'last', type: 'text', value: 'Lee' },
      { key: 'tags', label: 'tags', type: 'text', value: '["a"]' },
      { key: 'none', label: 'none', type: 'text', value: null }
    ]);
    expect(answerRows('', DEFINITION)).toEqual([]);
    expect(answerRows('[1]', DEFINITION)).toEqual([]);
  });

  it('reads what a processed submission wrote', () => {
    const outcome = JSON.stringify([
      { key: 'person', kind: 'person', objectName: 'Contact', recordId: '003', action: 'updated' },
      'skipped'
    ]);
    expect(writtenRecords(outcome)).toEqual([
      { key: 'person', kind: 'person', objectName: 'Contact', recordId: '003', action: 'updated' }
    ]);
    expect(writtenRecords(null)).toEqual([]);
    expect(writtenRecords('{')).toEqual([]);
  });

  it('offers Process Again only before processing, with a version, to someone who may edit', () => {
    const held = {
      id: 'a03',
      formName: 'Volunteer Interest',
      formVersionId: 'a02',
      status: 'Needs Review',
      message: 'Two people match.',
      answersJson: '{"last":"Lee"}',
      outcomeJson: null,
      definitionJson: DEFINITION
    };
    const view = submissionView(held, true);
    expect(view).toEqual(
      expect.objectContaining({
        id: 'a03',
        formName: 'Volunteer Interest',
        status: 'Needs Review',
        message: 'Two people match.',
        canProcess: true,
        records: []
      })
    );
    expect(view.answers[0].label).toBe('Last');
    expect(submissionView(held, false).canProcess).toBe(false);
    expect(submissionView({ ...held, formVersionId: null }, true).canProcess).toBe(false);
    expect(submissionView({ ...held, status: 'Processed' }, true).canProcess).toBe(false);
    expect(submissionView(null, true)).toBeNull();
  });
});
