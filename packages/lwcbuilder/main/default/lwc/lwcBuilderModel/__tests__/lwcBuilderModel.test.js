import { apexNames, CHART_HELPER } from 'c/lwcBuilderExportKit';
import {
  addBlock,
  addRow,
  addSection,
  bundleName,
  chartView,
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

  it('lays out a chart with two groupings and several totals (LB-07)', () => {
    const result = {
      title: 'Asks by Stage',
      measures: ['Sum of Amount', 'Record Count', 'Average Amount', 'Max Amount'],
      series: ['FY2025', 'FY2026'],
      groups: [
        {
          label: 'Won',
          cells: [
            [
              { value: 300, label: '$300' },
              { value: 3, label: '3' }
            ],
            [
              { value: 100, label: '$100' },
              { value: 1, label: '1' }
            ]
          ]
        },
        // A summary report's second grouping can be missing for a group.
        { label: 'Lost', cells: [null, [{ value: 150, label: '$150' }]] }
      ]
    };
    const grouped = chartView(result);
    expect(grouped.caption).toBe('Asks by Stage');
    expect(grouped.showMeasureNames).toBe(true);
    expect(grouped.groups[0].measures.map((m) => m.label)).toEqual([
      'Sum of Amount',
      'Record Count',
      'Average Amount'
    ]);
    const won = grouped.groups[0].measures[0].tracks;
    expect(won.map((t) => [t.label, t.value, t.segments[0].style])).toEqual([
      ['FY2025', '$300', 'width: 100%'],
      ['FY2026', '$100', 'width: 33%']
    ]);
    expect(grouped.groups[1].measures[0].tracks[0].value).toBe('');
    expect(grouped.groups[1].measures[1].tracks[1].segments[0].style).toBe('width: 0%');
    expect(grouped.legend.map((l) => l.swatch)).toEqual(['swatch tone0', 'swatch tone1']);
    expect(grouped.table.headers.map((h) => h.label)).toEqual([
      'FY2025: Sum of Amount',
      'FY2025: Record Count',
      'FY2025: Average Amount',
      'FY2026: Sum of Amount',
      'FY2026: Record Count',
      'FY2026: Average Amount'
    ]);
    expect(grouped.table.rows[1].cells.map((c) => c.value)).toEqual(['', '', '', '$150', '', '']);

    const stacked = chartView(result, 'stacked');
    const track = stacked.groups[0].measures[0].tracks;
    expect(track).toHaveLength(1);
    expect(track[0].value).toBe((400).toLocaleString());
    expect(track[0].segments.map((s) => s.style)).toEqual(['width: 75%', 'width: 25%']);
  });

  it('draws one bar per group for a single grouping, even when asked to stack', () => {
    const view = chartView(
      {
        title: 'Gifts',
        measures: ['Sum of Amount'],
        series: [],
        groups: [{ label: 'General', cells: [[{ value: -20 }]] }]
      },
      'stacked'
    );
    expect(view.caption).toBe('Gifts: Sum of Amount');
    expect(view.legend).toEqual([]);
    const [track] = view.groups[0].measures[0].tracks;
    expect([track.label, track.value, track.segments[0].css]).toEqual(['', '-20', 'segment']);
    expect(track.segments[0].style).toBe('width: 100%');
    expect(chartView(undefined).groups).toEqual([]);
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

  it('exports list and chart blocks that read through their own controller (LB-07)', () => {
    let { definition, left, right } = twoColumns();
    let related;
    let chart;
    ({ definition, id: related } = addBlock(definition, left, 'relatedList'));
    ({ definition, id: chart } = addBlock(definition, right, 'chart'));
    definition = updateItem(definition, related, {
      object: 'Gift__c',
      parentField: 'Donor__c',
      fields: ['Name', 'Amount__c'],
      orderBy: 'Gift_Date__c',
      direction: 'desc'
    });
    definition = updateItem(definition, chart, { report: 'Asks_By_Stage', display: 'stacked' });
    const { files } = exportSource(definition, { name: 'Giving', key: 'Giving', rowLimit: 25 });
    const byName = Object.fromEntries(files.map((file) => [file.name, file.content]));
    expect(Object.keys(byName)).toEqual([
      'giving.html',
      'giving.js',
      'giving.js-meta.xml',
      'giving.css',
      'GivingController.cls',
      'GivingController.cls-meta.xml',
      'GivingControllerTest.cls',
      'GivingControllerTest.cls-meta.xml'
    ]);
    const html = byName['giving.html'];
    expect(html).toContain(`data={lists.${related}.rows} columns={lists.${related}.columns}`);
    expect(html).toContain(`for:each={charts.${chart}.groups}`);
    expect(html).toContain('<table class="slds-assistive-text">');
    expect(html).not.toContain('<!--');
    const js = byName['giving.js'];
    expect(js).toContain("import records from '@salesforce/apex/GivingController.records';");
    expect(js).toContain("import chart from '@salesforce/apex/GivingController.chart';");
    expect(js).toContain('"parentField": "Donor__c"');
    expect(js).toContain('"rowLimit": 25');
    expect(js).toContain('"display": "stacked"');
    expect(js).toContain('Deploy GivingController with it.');
    expect(byName['GivingController.cls']).toContain('public with sharing class GivingController');
    expect(byName['GivingController.cls']).toContain('AccessLevel.USER_MODE');
    expect(byName['GivingControllerTest.cls']).toContain('GivingController.records(');
    expect(byName['giving.css']).toContain('--slds-g-color-palette-blue-40');

    // A bundle with no list or chart block needs no Apex.
    expect(exportSource(twoColumns().definition, { key: 'Plain' }).files).toHaveLength(3);
  });

  it('keeps the exported chart helper in step with chartView', () => {
    // The exported helper is source text; evaluating it here is the only way to run it.
    // eslint-disable-next-line no-new-func
    const exported = new Function(`${CHART_HELPER}\nreturn chartView;`)();
    const result = {
      title: 'Asks',
      measures: ['Sum of Amount', 'Record Count'],
      series: ['FY2025', 'FY2026'],
      groups: [
        { label: 'Won', cells: [[{ value: 30, label: '$30' }, { value: 3 }], [{ value: 10 }]] },
        { label: 'Lost', cells: [null, [{ value: 5 }]] }
      ]
    };
    for (const display of ['grouped', 'stacked']) {
      expect(exported(result, display)).toEqual(chartView(result, display));
    }
    expect(exported({ title: 'One', measures: ['Sum'], groups: [] })).toEqual(
      chartView({ title: 'One', measures: ['Sum'], groups: [] })
    );
    expect(apexNames('A'.repeat(50)).test).toHaveLength(40);
  });

  it('exports an LWC bundle with working markup', () => {
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
      'donorSnapshot.js-meta.xml',
      'DonorSnapshotController.cls',
      'DonorSnapshotController.cls-meta.xml',
      'DonorSnapshotControllerTest.cls',
      'DonorSnapshotControllerTest.cls-meta.xml'
    ]);
    expect(html).toContain('<lightning-output-field field-name="Email">');
    expect(html).toContain('Contact &lt;Info&gt;');
    expect(html).toContain(`data={lists.${list}.rows}`);
    expect(js).toContain('"rowLimit": 10');
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
