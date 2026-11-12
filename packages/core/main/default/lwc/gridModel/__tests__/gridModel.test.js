import {
  GRID_KEY,
  PARENT_COLUMN,
  columnsFor,
  flatRow,
  gridDocument,
  isSavedGrid,
  mergeDrafts,
  parentLabel,
  refusedDrafts,
  relatedRows,
  sourceOptions
} from 'c/gridModel';

const QUERY = { version: 1, object: 'Account', fields: ['Name', 'Phone', 'Owner.Name'] };

describe('c-grid-model', () => {
  it('tells saved grids from other saved queries and lists grids first', () => {
    const grid = gridDocument(QUERY, []);
    expect(isSavedGrid(grid)).toBe(true);
    expect(isSavedGrid(JSON.stringify(QUERY))).toBe(false);
    expect(isSavedGrid('not json')).toBe(false);

    const options = sourceOptions(
      [
        { recordId: 'q1', name: 'Donors', queryJson: JSON.stringify(QUERY) },
        { recordId: 'g1', name: 'Board', queryJson: grid }
      ],
      '{0} (grid)'
    );
    expect(options).toEqual([
      { label: 'Board (grid)', value: 'g1' },
      { label: 'Donors', value: 'q1' }
    ]);
  });

  it('keeps related record columns in the saved document and drops an empty list', () => {
    const children = [{ relationship: 'Contacts', fields: ['LastName'], limit: 10 }];
    const saved = JSON.parse(gridDocument({ ...QUERY, children: [{}] }, children));
    expect(saved.children).toEqual(children);
    expect(saved[GRID_KEY]).toEqual({ version: 1 });
    expect(JSON.parse(gridDocument({ ...QUERY, children: [{}] }, [])).children).toBeUndefined();
  });

  it('makes only own fields of editable types editable', () => {
    const fields = [
      { apiName: 'Name', label: 'Account Name', dataType: 'string' },
      { apiName: 'Phone', label: 'Phone', dataType: 'phone' },
      { apiName: 'CreatedDate', label: 'Created', dataType: 'datetime' }
    ];
    const columns = columnsFor(
      ['Name', 'Phone', 'CreatedDate', 'Owner.Name'],
      fields,
      new Set(['Name', 'CreatedDate', 'Owner.Name'])
    );
    expect(columns.map((column) => Boolean(column.editable))).toEqual([true, false, false, false]);
    expect(columns[1].type).toBe('phone');
    expect(columns[2].type).toBe('date');
    expect(columns[3].label).toBe('Owner.Name');
  });

  it('flattens rows and the related records of the chosen parents', () => {
    const rows = [
      { Id: 'a1', Name: 'Ruiz Household', Contacts: { records: [{ Id: 'c1', LastName: 'Ruiz' }] } },
      { Id: 'a2', Owner: { Name: 'Sam' }, Contacts: [{ Id: 'c2', LastName: 'Lee' }] }
    ];
    expect(flatRow(rows[1], ['Owner.Name'])).toEqual({ Id: 'a2', 'Owner.Name': 'Sam' });
    const child = { relationship: 'Contacts', fields: ['LastName'] };
    const label = (row) => parentLabel(row, ['Owner.Name']);

    const all = relatedRows(rows, child, [], label);
    expect(all).toEqual([
      { Id: 'c1', LastName: 'Ruiz', [PARENT_COLUMN]: 'Ruiz Household' },
      { Id: 'c2', LastName: 'Lee', [PARENT_COLUMN]: 'Sam' }
    ]);
    expect(relatedRows(rows, child, ['a2'], label).map((row) => row.Id)).toEqual(['c2']);
    expect(parentLabel({ Id: 'a3' }, [])).toBe('a3');
  });

  it('merges drafts by record and keeps only the refused ones after a save', () => {
    const drafts = mergeDrafts(
      [{ Id: 'a1', Name: 'One' }],
      [
        { Id: 'a1', Phone: '555' },
        { Id: 'a2', Name: 'Two' }
      ]
    );
    expect(drafts).toEqual([
      { Id: 'a1', Name: 'One', Phone: '555' },
      { Id: 'a2', Name: 'Two' }
    ]);

    const result = refusedDrafts(
      drafts,
      [{ recordId: 'a2', message: 'Required' }],
      (n) => `${n} failed`
    );
    expect(result.kept).toEqual([{ Id: 'a2', Name: 'Two' }]);
    expect(result.errors.rows.a2).toEqual({
      title: '1 failed',
      messages: ['Required'],
      fieldNames: ['Name']
    });
    expect(refusedDrafts(drafts, [], () => '').errors).toBeUndefined();
  });
});
