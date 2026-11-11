import {
  addBlock,
  addRow,
  addSection,
  bundleName,
  emptyDefinition,
  exportSource,
  isSafeImageUrl,
  isVisible,
  keyFromName,
  layoutOf,
  locate,
  moveBlock,
  moveItem,
  normalize,
  nudgeBlock,
  parseFieldList,
  removeItem,
  ruleFields,
  rulePermissions,
  setRowLayout,
  updateItem,
  validate
} from 'c/lwcBuilderModel';

function twoColumns() {
  let { definition, id: sectionId } = addSection(emptyDefinition(), 'At a Glance');
  ({ definition } = addRow(definition, sectionId, '6-6'));
  const [left, right] = definition.sections[0].rows[0].columns;
  return { definition, sectionId, left: left.id, right: right.id };
}

describe('lwcBuilderModel', () => {
  it('builds sections, rows and columns with unique ids and never changes the input', () => {
    const start = emptyDefinition();
    const { definition, left, right } = twoColumns();
    expect(start.sections).toHaveLength(0);
    expect(definition.sections[0].title).toBe('At a Glance');
    expect(left).not.toBe(right);
    expect(layoutOf(definition.sections[0].rows[0])).toBe('6-6');
    expect(validate(definition)).toEqual([]);
  });

  it('adds, moves and nudges blocks between columns', () => {
    let { definition, left, right } = twoColumns();
    let first;
    let second;
    ({ definition, id: first } = addBlock(definition, left, 'text'));
    ({ definition, id: second } = addBlock(definition, left, 'image', first));
    expect(locate(definition, left).item.blocks.map((b) => b.id)).toEqual([second, first]);

    definition = moveBlock(definition, second, right);
    expect(locate(definition, right).item.blocks.map((b) => b.id)).toEqual([second]);

    definition = nudgeBlock(definition, second, 'left');
    expect(locate(definition, left).item.blocks.map((b) => b.id)).toEqual([first, second]);
    definition = nudgeBlock(definition, second, 'up');
    expect(locate(definition, left).item.blocks.map((b) => b.id)).toEqual([second, first]);
    expect(nudgeBlock(definition, second, 'up')).toBe(definition);
    expect(nudgeBlock(definition, second, 'left')).toBe(definition);
    expect(addBlock(definition, left, 'script').id).toBeNull();
  });

  it('keeps every block when a row gets fewer columns', () => {
    let { definition, right } = twoColumns();
    ({ definition } = addBlock(definition, right, 'text'));
    const rowId = definition.sections[0].rows[0].id;
    definition = setRowLayout(definition, rowId, '12');
    const row = locate(definition, rowId).item;
    expect(row.columns).toHaveLength(1);
    expect(row.columns[0].width).toBe(12);
    expect(row.columns[0].blocks).toHaveLength(1);
    definition = setRowLayout(definition, rowId, '3-3-3-3');
    expect(locate(definition, rowId).item.columns.map((c) => c.width)).toEqual([3, 3, 3, 3]);
    expect(validate(definition)).toEqual([]);
  });

  it('moves and removes sections and rows', () => {
    let { definition } = twoColumns();
    let second;
    ({ definition, id: second } = addSection(definition, 'Second'));
    definition = moveItem(definition, second, -1);
    expect(definition.sections[0].title).toBe('Second');
    definition = removeItem(definition, second);
    expect(definition.sections.map((s) => s.title)).toEqual(['At a Glance']);
  });

  it('says what each block is missing', () => {
    let { definition, left } = twoColumns();
    const ids = {};
    for (const type of ['fields', 'relatedList', 'chart', 'image', 'action']) {
      ({ definition, id: ids[type] } = addBlock(definition, left, type));
    }
    const codes = validate(definition).map((problem) => `${problem.id}:${problem.code}`);
    expect(codes).toEqual(
      expect.arrayContaining([
        `${ids.fields}:fieldsNeeded`,
        `${ids.relatedList}:objectNeeded`,
        `${ids.relatedList}:parentFieldNeeded`,
        `${ids.chart}:reportNeeded`,
        `${ids.image}:imageUrl`,
        `${ids.image}:imageAlt`,
        `${ids.action}:labelNeeded`,
        `${ids.action}:actionNeeded`
      ])
    );
    definition = updateItem(definition, ids.image, {
      url: ['javascript', 'alert(1)'].join(':'),
      altText: 'Logo',
      id: 'x'
    });
    expect(locate(definition, ids.image)).not.toBeNull();
    expect(validate(definition).some((p) => p.id === ids.image && p.code === 'imageUrl')).toBe(
      true
    );
  });

  it('accepts only Salesforce-relative or https images', () => {
    expect(isSafeImageUrl('/resource/Logo')).toBe(true);
    expect(isSafeImageUrl('https://example.org/a.png')).toBe(true);
    expect(isSafeImageUrl('//evil.example/a.png')).toBe(false);
    expect(isSafeImageUrl('http://example.org/a.png')).toBe(false);
    expect(isSafeImageUrl('data:image/png;base64,AAAA')).toBe(false);
  });

  it('evaluates visibility rules as display rules', () => {
    const record = { MailingCity: 'Boston', Phone: '' };
    expect(isVisible(undefined, record, {})).toBe(true);
    expect(
      isVisible(
        { type: 'field', field: 'MailingCity', operator: 'equals', value: 'Boston' },
        record
      )
    ).toBe(true);
    expect(
      isVisible(
        { type: 'field', field: 'MailingCity', operator: 'notEquals', value: 'Boston' },
        record
      )
    ).toBe(false);
    expect(
      isVisible({ type: 'field', field: 'MailingCity', operator: 'contains', value: 'bos' }, record)
    ).toBe(true);
    expect(isVisible({ type: 'field', field: 'Phone', operator: 'isBlank' }, record)).toBe(true);
    expect(isVisible({ type: 'field', field: 'Hidden__c', operator: 'isNotBlank' }, record)).toBe(
      false
    );
    expect(
      isVisible({ type: 'permission', permission: 'Can_See' }, record, { Can_See: true })
    ).toBe(true);
    expect(isVisible({ type: 'permission', permission: 'Can_See', has: false }, record, {})).toBe(
      true
    );
  });

  it('collects the fields and permissions the rules read', () => {
    let { definition, left } = twoColumns();
    let a;
    let b;
    ({ definition, id: a } = addBlock(definition, left, 'text'));
    ({ definition, id: b } = addBlock(definition, left, 'text'));
    definition = updateItem(definition, a, {
      visibility: { type: 'field', field: 'Status__c', operator: 'equals' }
    });
    definition = updateItem(definition, b, {
      visibility: { type: 'permission', permission: 'Board_View' }
    });
    expect(ruleFields(definition)).toEqual(['Status__c']);
    expect(rulePermissions(definition)).toEqual(['Board_View']);
  });

  it('normalizes stored text and names keys and bundles', () => {
    expect(normalize('not json').sections).toEqual([]);
    expect(
      normalize({ sections: [{ id: 's1', rows: [{ id: 'r1', columns: [{ id: 'c1' }] }] }] })
        .sections[0].rows[0].columns[0]
    ).toEqual({
      id: 'c1',
      width: 12,
      blocks: []
    });
    expect(parseFieldList('Name, Email  Name,Phone')).toEqual(['Name', 'Email', 'Phone']);
    expect(keyFromName('Donor Snapshot!')).toBe('Donor_Snapshot');
    expect(keyFromName('2026 Gala')).toBe('C_2026_Gala');
    expect(bundleName('Donor_Snapshot')).toBe('donorSnapshot');
  });

  it('exports an LWC bundle with working markup and placeholders', () => {
    let { definition, left, right } = twoColumns();
    let fields;
    let list;
    let flow;
    let action;
    ({ definition, id: fields } = addBlock(definition, left, 'fields'));
    ({ definition, id: list } = addBlock(definition, right, 'recordList'));
    ({ definition, id: flow } = addBlock(definition, right, 'action'));
    ({ definition, id: action } = addBlock(definition, right, 'action'));
    definition = updateItem(definition, fields, { fields: ['Email'], title: 'Contact <Info>' });
    definition = updateItem(definition, list, { object: 'Contact', fields: ['Name'] });
    definition = updateItem(definition, flow, {
      label: 'Run',
      flowName: 'Thank_You',
      passRecordId: true
    });
    definition = updateItem(definition, action, {
      label: 'Task',
      kind: 'quickAction',
      actionName: 'Global.NewTask'
    });

    const { bundle, files } = exportSource(definition, {
      name: 'Donor Snapshot',
      key: 'Donor_Snapshot',
      objectName: 'Contact'
    });
    const [html, js, meta] = files.map((file) => file.content);
    expect(bundle).toBe('donorSnapshot');
    expect(files.map((file) => file.name)).toEqual([
      'donorSnapshot.html',
      'donorSnapshot.js',
      'donorSnapshot.js-meta.xml'
    ]);
    expect(html).toContain('<lightning-output-field field-name="Email">');
    expect(html).toContain('Contact &lt;Info&gt;');
    expect(html).toContain('Record List block: Contact');
    expect(html).toContain('flow-api-name="Thank_You"');
    expect(html).toContain('data-action="Global.NewTask"');
    expect(js).toContain(
      'export default class DonorSnapshot extends NavigationMixin(LightningElement)'
    );
    expect(js).toContain("type: 'standard__quickAction'");
    expect(meta).toContain('<target>lightning__RecordPage</target>');
    expect(meta).not.toContain('lightning__HomePage');
  });
});
